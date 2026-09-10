import { Context, Next } from 'hono';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { db } from '../db/index.js';
import { users } from '../db/schema/index.js';
import { eq } from 'drizzle-orm';
import { AppError } from './error-handler.js';

export interface AuthUser {
  id: string;
  email: string;
  username: string | null;
  role: string;
  suspended: boolean;
  isPrivate: boolean;
}

declare module 'hono' {
  interface ContextVariableMap {
    user: AuthUser;
    uid: string;
  }
}

export async function requireAuth(c: Context, next: Next) {
  const authHeader = c.req.header('Authorization') || c.req.header('authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new AppError('Authentication required. Missing or malformed Bearer token', 401, 'UNAUTHORIZED');
  }

  const token = authHeader.substring(7).trim();
  let decoded: { sub: string; email: string };
  try {
    decoded = jwt.verify(token, env.JWT_SECRET) as { sub: string; email: string };
  } catch (err: unknown) {
    const isExpired = (err as { name?: string })?.name === 'TokenExpiredError';
    throw new AppError(
      isExpired ? 'Session expired. Please refresh your token' : 'Invalid authorization token',
      401,
      isExpired ? 'TOKEN_EXPIRED' : 'INVALID_TOKEN',
    );
  }

  const userResult = await db
    .select({
      id: users.id,
      email: users.email,
      username: users.username,
      role: users.role,
      suspended: users.suspended,
      isPrivate: users.isPrivate,
      deletedAt: users.deletedAt,
    })
    .from(users)
    .where(eq(users.id, decoded.sub))
    .limit(1);

  const user = userResult[0];
  if (!user || user.deletedAt) {
    throw new AppError('Account does not exist or has been deleted', 401, 'ACCOUNT_NOT_FOUND');
  }

  if (user.suspended) {
    throw new AppError('Your account has been suspended by administration', 403, 'ACCOUNT_SUSPENDED');
  }

  c.set('user', user);
  c.set('uid', user.id);

  await next();
}

export async function optionalAuth(c: Context, next: Next) {
  const authHeader = c.req.header('Authorization') || c.req.header('authorization');
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.substring(7).trim();
    try {
      const decoded = jwt.verify(token, env.JWT_SECRET) as { sub: string };
      const userResult = await db
        .select({
          id: users.id,
          email: users.email,
          username: users.username,
          role: users.role,
          suspended: users.suspended,
          isPrivate: users.isPrivate,
          deletedAt: users.deletedAt,
        })
        .from(users)
        .where(eq(users.id, decoded.sub))
        .limit(1);

      const user = userResult[0];
      if (user && !user.deletedAt && !user.suspended) {
        c.set('user', user);
        c.set('uid', user.id);
      }
    } catch {
      // Ignore token errors on optional auth
    }
  }

  await next();
}
