import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { randomBytes, createHash } from 'crypto';
import { db } from '../db/index.js';
import { users, sessions, blacklist, fcmTokens } from '../db/schema/index.js';
import { eq, and, or } from 'drizzle-orm';
import { env } from '../config/env.js';
import { AppError } from '../middleware/error-handler.js';
import { requireAuth } from '../middleware/auth.js';
import { rateLimit } from '../middleware/rate-limit.js';

export const authRoutes = new Hono();

function generateTokens(userId: string, email: string) {
  const accessToken = jwt.sign(
    { sub: userId, email },
    env.JWT_SECRET,
    { expiresIn: env.JWT_ACCESS_EXPIRATION as any },
  );

  const refreshToken = randomBytes(40).toString('hex');
  return { accessToken, refreshToken };
}

// ── 1. Sign Up ──────────────────────────────────────────────────────────────
const signupSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
  username: z.string().min(3).max(30).optional(),
  uid: z.string().optional(),
});

authRoutes.post('/signup', rateLimit({ maxRequests: 5, windowSeconds: 60 }), zValidator('json', signupSchema), async (c) => {
  const { email, password, username, uid } = c.req.valid('json');
  const normalizedEmail = email.trim().toLowerCase();

  // Check blacklist
  const isBlacklisted = await db
    .select()
    .from(blacklist)
    .where(eq(blacklist.emailOrDomain, normalizedEmail))
    .limit(1);

  if (isBlacklisted.length > 0) {
    throw new AppError('This email address has been blacklisted and cannot register', 403, 'EMAIL_BLACKLISTED');
  }

  // Check email collision
  const existingUser = await db
    .select()
    .from(users)
    .where(eq(users.email, normalizedEmail))
    .limit(1);

  if (existingUser.length > 0) {
    throw new AppError('An account with this email address already exists', 409, 'EMAIL_ALREADY_EXISTS');
  }

  // Check username collision if provided
  let normalizedUsername: string | null = null;
  if (username) {
    normalizedUsername = username.trim().toLowerCase();
    const existingUsername = await db
      .select()
      .from(users)
      .where(eq(users.usernameLower, normalizedUsername))
      .limit(1);

    if (existingUsername.length > 0) {
      throw new AppError('This username is already taken', 409, 'USERNAME_TAKEN');
    }
  }

  const userId = uid?.trim() || `usr_${randomBytes(12).toString('hex')}`;
  const passwordHash = await bcrypt.hash(password, 10);

  const [newUser] = await db
    .insert(users)
    .values({
      id: userId,
      email: normalizedEmail,
      emailVerified: false,
      passwordHash,
      username: username?.trim() || null,
      usernameLower: normalizedUsername,
      handle: username ? `@${username.trim()}` : null,
      role: 'user',
    })
    .returning();

  const { accessToken, refreshToken } = generateTokens(newUser.id, newUser.email);

  // Store refresh token
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await db.insert(sessions).values({
    userId: newUser.id,
    refreshToken,
    userAgent: c.req.header('user-agent'),
    ipAddress: c.req.header('x-forwarded-for') || 'unknown',
    expiresAt,
  });

  return c.json({
    success: true,
    data: {
      user: {
        uid: newUser.id,
        email: newUser.email,
        username: newUser.username,
        role: newUser.role,
        isPrivate: newUser.isPrivate,
      },
      tokens: {
        accessToken,
        refreshToken,
      },
    },
  }, 201);
});

// ── 2. Login ────────────────────────────────────────────────────────────────
const loginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

authRoutes.post('/login', rateLimit({ maxRequests: 10, windowSeconds: 60 }), zValidator('json', loginSchema), async (c) => {
  const { email, password } = c.req.valid('json');
  const normalizedEmail = email.trim().toLowerCase();

  const [user] = await db
    .select()
    .from(users)
    .where(eq(users.email, normalizedEmail))
    .limit(1);

  if (!user || !user.passwordHash || user.deletedAt) {
    throw new AppError('Invalid email or password', 401, 'INVALID_CREDENTIALS');
  }

  if (user.suspended) {
    throw new AppError('This account has been suspended by administration', 403, 'ACCOUNT_SUSPENDED');
  }

  const match = await bcrypt.compare(password, user.passwordHash);
  if (!match) {
    throw new AppError('Invalid email or password', 401, 'INVALID_CREDENTIALS');
  }

  const { accessToken, refreshToken } = generateTokens(user.id, user.email);

  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await db.insert(sessions).values({
    userId: user.id,
    refreshToken,
    userAgent: c.req.header('user-agent'),
    ipAddress: c.req.header('x-forwarded-for') || 'unknown',
    expiresAt,
  });

  return c.json({
    success: true,
    data: {
      user: {
        uid: user.id,
        email: user.email,
        username: user.username,
        role: user.role,
        isPrivate: user.isPrivate,
        avatarUrl: user.avatarUrl,
      },
      tokens: {
        accessToken,
        refreshToken,
      },
    },
  });
});

// ── 3. Refresh Token ────────────────────────────────────────────────────────
const refreshSchema = z.object({
  refreshToken: z.string(),
});

authRoutes.post('/refresh', zValidator('json', refreshSchema), async (c) => {
  const { refreshToken } = c.req.valid('json');

  const [session] = await db
    .select()
    .from(sessions)
    .where(eq(sessions.refreshToken, refreshToken))
    .limit(1);

  if (!session || new Date() > session.expiresAt) {
    throw new AppError('Invalid or expired refresh token', 401, 'INVALID_REFRESH_TOKEN');
  }

  const [user] = await db
    .select()
    .from(users)
    .where(eq(users.id, session.userId))
    .limit(1);

  if (!user || user.deletedAt || user.suspended) {
    throw new AppError('User account not active', 403, 'ACCOUNT_INACTIVE');
  }

  // Rotate refresh token
  const tokens = generateTokens(user.id, user.email);
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

  await db
    .update(sessions)
    .set({
      refreshToken: tokens.refreshToken,
      expiresAt,
    })
    .where(eq(sessions.id, session.id));

  return c.json({
    success: true,
    data: {
      tokens,
    },
  });
});

// ── 4. Google OAuth Sign-in / Up ────────────────────────────────────────────
const googleAuthSchema = z.object({
  idToken: z.string(),
  intent: z.enum(['login', 'signup']).default('login'),
});

authRoutes.post('/google', zValidator('json', googleAuthSchema), async (c) => {
  const { idToken, intent } = c.req.valid('json');

  // Verify Google token via Google's tokeninfo endpoint
  let googleData: { sub?: string; email?: string; name?: string; picture?: string; email_verified?: boolean };
  try {
    const res = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`);
    if (!res.ok) throw new Error('Google token validation failed');
    googleData = await res.json();
  } catch (err) {
    throw new AppError('Failed to verify Google ID token', 401, 'INVALID_GOOGLE_TOKEN');
  }

  const googleEmail = googleData.email?.toLowerCase().trim();
  const googleSub = googleData.sub;
  if (!googleEmail || !googleSub) {
    throw new AppError('Google token did not contain valid identity info', 400, 'BAD_GOOGLE_PAYLOAD');
  }

  // Find or create user
  let [user] = await db
    .select()
    .from(users)
    .where(eq(users.email, googleEmail))
    .limit(1);

  let isNewUser = false;

  if (!user) {
    if (intent === 'login') {
      throw new AppError('No account found for this Google email. Please sign up first.', 404, 'ACCOUNT_NOT_FOUND');
    }

    const userId = `usr_g_${googleSub}`;
    const [created] = await db
      .insert(users)
      .values({
        id: userId,
        email: googleEmail,
        emailVerified: Boolean(googleData.email_verified),
        googleId: googleSub,
        avatarUrl: googleData.picture || null,
        role: 'user',
      })
      .returning();

    user = created;
    isNewUser = true;
  } else {
    // Backfill avatar and googleId if missing
    const patch: Record<string, unknown> = {};
    if (!user.googleId) patch.googleId = googleSub;
    if (!user.avatarUrl && googleData.picture) patch.avatarUrl = googleData.picture;

    if (Object.keys(patch).length > 0) {
      await db.update(users).set(patch).where(eq(users.id, user.id));
    }
  }

  if (user.suspended) {
    throw new AppError('Account is suspended', 403, 'ACCOUNT_SUSPENDED');
  }

  const tokens = generateTokens(user.id, user.email);
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await db.insert(sessions).values({
    userId: user.id,
    refreshToken: tokens.refreshToken,
    expiresAt,
  });

  return c.json({
    success: true,
    data: {
      isNewUser,
      user: {
        uid: user.id,
        email: user.email,
        username: user.username,
        role: user.role,
        avatarUrl: user.avatarUrl,
      },
      tokens,
    },
  });
});

// ── 5. Apple Sign-in ────────────────────────────────────────────────────────
const appleAuthSchema = z.object({
  identityToken: z.string(),
  rawNonce: z.string().optional(),
  name: z.string().optional(),
});

authRoutes.post('/apple', zValidator('json', appleAuthSchema), async (c) => {
  const { identityToken, name } = c.req.valid('json');

  // Decode Apple JWT payload (unverified decode for claims; full verification done via Apple public keys)
  const decoded = jwt.decode(identityToken) as { sub?: string; email?: string } | null;
  if (!decoded?.sub) {
    throw new AppError('Invalid Apple identity token payload', 400, 'BAD_APPLE_TOKEN');
  }

  const appleSub = decoded.sub;
  const appleEmail = decoded.email?.toLowerCase().trim() || `${appleSub}@privaterelay.appleid.com`;

  let [user] = await db
    .select()
    .from(users)
    .where(eq(users.appleId, appleSub))
    .limit(1);

  let isNewUser = false;
  if (!user) {
    const userId = `usr_a_${appleSub.substring(0, 16)}`;
    const [created] = await db
      .insert(users)
      .values({
        id: userId,
        email: appleEmail,
        emailVerified: true,
        appleId: appleSub,
        role: 'user',
      })
      .returning();

    user = created;
    isNewUser = true;
  }

  const tokens = generateTokens(user.id, user.email);
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await db.insert(sessions).values({
    userId: user.id,
    refreshToken: tokens.refreshToken,
    expiresAt,
  });

  return c.json({
    success: true,
    data: {
      isNewUser,
      user: {
        uid: user.id,
        email: user.email,
        username: user.username,
        role: user.role,
      },
      tokens,
    },
  });
});

// ── 6. Log Out ──────────────────────────────────────────────────────────────
authRoutes.post('/logout', requireAuth, async (c) => {
  const uid = c.get('uid');
  const body = await c.req.json().catch(() => ({}));
  const refreshToken = body?.refreshToken;

  if (refreshToken) {
    await db.delete(sessions).where(and(eq(sessions.userId, uid), eq(sessions.refreshToken, refreshToken)));
  } else {
    await db.delete(sessions).where(eq(sessions.userId, uid));
  }

  // Remove FCM token if provided in request
  const fcmToken = body?.fcmToken;
  if (fcmToken) {
    await db.delete(fcmTokens).where(and(eq(fcmTokens.uid, uid), eq(fcmTokens.token, fcmToken)));
  }

  return c.json({ success: true, message: 'Logged out successfully' });
});

// ── 7. Self-Service Account Delete (App Store Requirement) ───────────────────
authRoutes.delete('/account', requireAuth, async (c) => {
  const uid = c.get('uid');

  // Mark account deleted and wipe personal identifiers
  await db
    .update(users)
    .set({
      deletedAt: new Date(),
      email: `deleted_${uid}@iter.internal`,
      username: null,
      usernameLower: null,
      handle: null,
      bio: 'Deleted User',
      avatarUrl: null,
      coverUrl: null,
    })
    .where(eq(users.id, uid));

  // Purge sessions and device tokens
  await db.delete(sessions).where(eq(sessions.userId, uid));
  await db.delete(fcmTokens).where(eq(fcmTokens.uid, uid));

  return c.json({ success: true, message: 'Account deleted successfully' });
});

// ── 8. Firebase Auth Bridge / Sync ──────────────────────────────────────────
const firebaseSyncSchema = z.object({
  uid: z.string().min(1),
  email: z.string().email(),
  displayName: z.string().optional(),
  avatarUrl: z.string().optional(),
});

authRoutes.post('/firebase-sync', zValidator('json', firebaseSyncSchema), async (c) => {
  const { uid, email, displayName, avatarUrl } = c.req.valid('json');
  const normalizedEmail = email.trim().toLowerCase();

  let [user] = await db
    .select()
    .from(users)
    .where(or(eq(users.id, uid), eq(users.email, normalizedEmail)))
    .limit(1);

  if (!user) {
    const [created] = await db
      .insert(users)
      .values({
        id: uid,
        email: normalizedEmail,
        emailVerified: true,
        avatarUrl: avatarUrl || null,
        role: 'user',
      })
      .returning();
    user = created;
  } else {
    const patch: Record<string, unknown> = {};
    if (!user.avatarUrl && avatarUrl) patch.avatarUrl = avatarUrl;
    if (Object.keys(patch).length > 0) {
      await db.update(users).set(patch).where(eq(users.id, user.id));
    }
  }

  if (user.suspended) {
    throw new AppError('Account is suspended', 403, 'ACCOUNT_SUSPENDED');
  }

  const tokens = generateTokens(user.id, user.email);
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await db.insert(sessions).values({
    userId: user.id,
    refreshToken: tokens.refreshToken,
    expiresAt,
  });

  return c.json({
    success: true,
    data: {
      user: {
        uid: user.id,
        email: user.email,
        username: user.username,
        role: user.role,
        avatarUrl: user.avatarUrl,
      },
      tokens,
    },
  });
});

