import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { db } from '../db/index.js';
import { events, eventRegistrations, eventChatMessages, users, notifications } from '../db/schema/index.js';
import { eq, and, sql, desc, inArray } from 'drizzle-orm';
import { AppError } from '../middleware/error-handler.js';
import { requireAuth, optionalAuth } from '../middleware/auth.js';
import { requireRole } from '../middleware/rbac.js';
import { sendPushNotification } from '../services/fcm.service.js';
import { randomBytes } from 'crypto';

export const eventRoutes = new Hono();

function formatEvent(e: typeof events.$inferSelect) {
  return {
    ...e,
    imageUrls: e.coverImageUrl ? [e.coverImageUrl] : [],
  };
}

// ── 1. List Events ──────────────────────────────────────────────────────────
eventRoutes.get('/', optionalAuth, async (c) => {
  const type = c.req.query('type');
  const country = c.req.query('country')?.trim().toLowerCase();
  const limit = Math.min(Number(c.req.query('limit')) || 30, 100);

  const conditions = [];
  if (type && type !== 'All') conditions.push(eq(events.eventType, type));
  if (country && country !== 'all') conditions.push(eq(events.locationCountry, country));

  const eventList = await db
    .select()
    .from(events)
    .where(conditions.length > 0 ? and(...conditions) : undefined)
    .orderBy(desc(events.createdAt))
    .limit(limit);

  return c.json({ success: true, data: eventList.map(formatEvent) });
});

// ── 2. Get Single Event ─────────────────────────────────────────────────────
eventRoutes.get('/:id', optionalAuth, async (c) => {
  const eventId = c.req.param('id')!;
  const viewerUid = c.get('uid');

  const [event] = await db.select().from(events).where(eq(events.id, eventId)).limit(1);
  if (!event) throw new AppError('Event not found', 404, 'NOT_FOUND');

  let myRegistration = null;
  if (viewerUid) {
    const [reg] = await db
      .select()
      .from(eventRegistrations)
      .where(and(eq(eventRegistrations.eventId, eventId), eq(eventRegistrations.userUid, viewerUid)))
      .limit(1);
    myRegistration = reg || null;
  }

  return c.json({
    success: true,
    data: {
      ...formatEvent(event),
      myRegistration,
    },
  });
});

// ── 3. Create Event (Admin or Org Admin) ────────────────────────────────────
const createEventSchema = z.object({
  title: z.string().min(3).max(150),
  description: z.string().min(5),
  location: z.string(),
  locationCountry: z.string(),
  eventType: z.string(),
  coverImageUrl: z.string().optional(),
  imageUrls: z.array(z.string()).optional(),
  linkUrl: z.string().optional(),
  startDate: z.string().optional(),
  endDate: z.string().optional(),
  capacity: z.number().optional(),
  isOnline: z.boolean().default(false),
  lat: z.number().optional(),
  lng: z.number().optional(),
});

eventRoutes.post('/', requireAuth, requireRole(['admin', 'org_admin']), zValidator('json', createEventSchema), async (c) => {
  const uid = c.get('uid');
  const body = c.req.valid('json');

  const [author] = await db.select().from(users).where(eq(users.id, uid)).limit(1);
  const eventId = `evt_${randomBytes(12).toString('hex')}`;
  const countryClean = body.locationCountry.trim().toLowerCase();
  const resolvedCoverImageUrl = body.coverImageUrl || body.imageUrls?.[0] || null;

  await db
    .insert(events)
    .values({
      id: eventId,
      title: body.title,
      description: body.description,
      location: body.location,
      locationCountry: countryClean,
      eventType: body.eventType,
      coverImageUrl: resolvedCoverImageUrl,
      linkUrl: body.linkUrl || null,
      startDate: body.startDate ? new Date(body.startDate) : null,
      endDate: body.endDate ? new Date(body.endDate) : null,
      capacity: body.capacity || null,
      authorUid: uid,
      authorUsername: author?.username || 'admin',
      authorAvatar: author?.avatarUrl || null,
      isOnline: body.isOnline,
      lat: body.lat || null,
      lng: body.lng || null,
    });

  const [newEvent] = await db.select().from(events).where(eq(events.id, eventId)).limit(1);

  // Async fan-out notifications based on user's eventNotifPrefs
  (async () => {
    try {
      const eligibleUsers = await db.select({ id: users.id, prefs: users.eventNotifPrefs }).from(users).where(eq(users.suspended, false));
      for (const u of eligibleUsers) {
        if (u.id === uid) continue;
        const prefs = u.prefs;
        if (prefs.mode === 'off') continue;
        if (prefs.types.length > 0 && !prefs.types.includes(body.eventType)) continue;
        if (prefs.countries.length > 0 && !prefs.countries.includes(countryClean)) continue;

        await db.insert(notifications).ignore().values({
          id: `new_event_${eventId}_${u.id}`,
          targetUid: u.id,
          actorUid: '',
          type: 'new_event',
          targetId: eventId,
          title: body.title,
          subtitle: body.location,
        });

        sendPushNotification({
          targetUid: u.id,
          title: 'New event',
          body: `${body.title} — ${body.location}`,
          type: 'new_event',
          targetId: eventId,
        });
      }
    } catch (e) {
      console.error('[Event Notification Fanout Error]', e);
    }
  })();

  return c.json({ success: true, data: newEvent }, 201);
});

// ── 4. Submit Registration ──────────────────────────────────────────────────
const registerEventSchema = z.object({
  name: z.string().min(2),
  email: z.string().email(),
  phone: z.string().min(5),
  countryCode: z.string().min(1),
});

eventRoutes.post('/:id/register', requireAuth, zValidator('json', registerEventSchema), async (c) => {
  const eventId = c.req.param('id')!;
  const uid = c.get('uid');
  const { name, email, phone, countryCode } = c.req.valid('json');

  const [event] = await db.select().from(events).where(eq(events.id, eventId)).limit(1);
  if (!event) throw new AppError('Event not found', 404, 'NOT_FOUND');

  const regId = `${eventId}_${uid}`;
  await db
    .insert(eventRegistrations)
    .values({
      id: regId,
      eventId,
      eventTitle: event.title,
      userUid: uid,
      name,
      email,
      phone,
      countryCode,
      status: 'pending',
    })
    .onDuplicateKeyUpdate({
      set: { name, email, phone, countryCode, status: 'pending' },
    });

  const [registration] = await db.select().from(eventRegistrations).where(eq(eventRegistrations.id, regId)).limit(1);

  return c.json({ success: true, data: registration }, 201);
});

// ── 5. Review Registration (Approve / Reject) ───────────────────────────────
const reviewRegSchema = z.object({
  status: z.enum(['approved', 'rejected']),
});

eventRoutes.patch('/registrations/:regId', requireAuth, requireRole(['admin', 'org_admin']), zValidator('json', reviewRegSchema), async (c) => {
  const regId = c.req.param('regId')!;
  const reviewerUid = c.get('uid');
  const { status } = c.req.valid('json');

  await db
    .update(eventRegistrations)
    .set({
      status,
      reviewedAt: new Date(),
      reviewedBy: reviewerUid,
    })
    .where(eq(eventRegistrations.id, regId));

  const [reg] = await db.select().from(eventRegistrations).where(eq(eventRegistrations.id, regId)).limit(1);

  if (!reg) throw new AppError('Registration not found', 404, 'NOT_FOUND');

  // Notify applicant
  await sendPushNotification({
    targetUid: reg.userUid,
    title: status === 'approved' ? 'Registration Approved' : 'Registration Status Update',
    body: `Your registration for "${reg.eventTitle}" was ${status}.`,
    type: 'event_registration_update',
    targetId: reg.eventId,
  });

  return c.json({ success: true, data: reg });
});
