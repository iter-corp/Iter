import * as admin from 'firebase-admin';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

const db = admin.firestore();

const MAX_BATCH_WRITES = 450;

type NotifMode = 'all' | 'cities' | 'off';

interface EventNotifPrefs {
  mode: NotifMode;
  cities: string[];
  types: string[];
}

function parsePrefs(raw: unknown): EventNotifPrefs {
  const m = (raw ?? {}) as Record<string, unknown>;
  const modeStr = String(m.mode ?? 'all');
  const mode: NotifMode =
    modeStr === 'cities' ? 'cities' : modeStr === 'off' ? 'off' : 'all';
  const cities = Array.isArray(m.cities)
    ? (m.cities as unknown[]).map((c) => String(c).trim().toLowerCase()).filter((c) => c.length > 0)
    : [];
  const types = Array.isArray(m.types)
    ? (m.types as unknown[]).map((t) => String(t))
    : [];
  return { mode, cities, types };
}

function wantsThisEvent(prefs: EventNotifPrefs, eventCity: string, eventType: string): boolean {
  if (prefs.mode === 'off') return false;
  if (prefs.mode === 'cities') {
    if (eventCity.length === 0) return false;
    if (!prefs.cities.includes(eventCity)) return false;
  }
  if (prefs.types.length > 0) {
    // If the admin didn't tag a type, treat it as matching only when the user
    // has no type filter (handled above) — here a missing type fails the filter.
    if (eventType.length === 0) return false;
    if (!prefs.types.includes(eventType)) return false;
  }
  return true;
}

/**
 * When an event is published, fan out a `new_event` notification to every user
 * whose `eventNotifPrefs` matches (all events / selected cities / by type).
 * The push is delivered by `sendPushOnNotificationCreate` in notifications.ts.
 *
 * TODO(scale): this reads the entire `users` collection per event and writes a
 *   notification doc per match (each of which triggers another function for the
 *   push). Fine for a small user base; at scale, query by
 *   `eventNotifPrefs.mode` / `eventNotifPrefs.cities` (needs a composite index)
 *   and/or chunk the work through a task queue.
 * NOTE(city matching): `eventCity` vs the user's chosen cities is a normalized
 *   string compare (lowercase, first comma segment). It won't match alternate
 *   spellings / languages (e.g. "Erbil" vs "Hawler"); users in `cities` mode
 *   may therefore miss events. The settings screen warns about this.
 */
export const onEventCreate = onDocumentCreated('events/{eventId}', async (event) => {
  const eventId = event.params.eventId;
  const data = event.data?.data();
  if (!data) return;

  const title = String(data.title ?? '').trim();
  const location = String(data.location ?? '').trim();
  const eventCity = String(
    data.locationCity ?? location.split(',')[0] ?? '',
  ).trim().toLowerCase();
  const eventType = String(data.eventType ?? '').trim();

  const usersSnap = await db.collection('users').get();

  let batch = db.batch();
  let writes = 0;
  let queued = 0;

  for (const userDoc of usersSnap.docs) {
    const u = userDoc.data();
    if (u.suspended === true) continue;
    const prefs = parsePrefs(u.eventNotifPrefs);
    if (!wantsThisEvent(prefs, eventCity, eventType)) continue;

    const notifRef = db
      .collection('notifications')
      .doc(userDoc.id)
      .collection('items')
      .doc(`new_event_${eventId}`);
    batch.set(notifRef, {
      type: 'new_event',
      actorUid: '',
      targetId: eventId,
      title,
      subtitle: location,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    writes++;
    queued++;

    if (writes >= MAX_BATCH_WRITES) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }

  if (writes > 0) {
    await batch.commit();
  }

  // Keep a small audit trail on the event doc.
  await db.collection('events').doc(eventId).set(
    { notifiedUserCount: queued, notifiedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true },
  );
});
