import * as admin from 'firebase-admin';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

const db = admin.firestore();

const MAX_BATCH_WRITES = 450;

type NotifMode = 'all' | 'off';

interface EventNotifPrefs {
  mode: NotifMode;
  types: string[];
  countries: string[];
}

function parsePrefs(raw: unknown): EventNotifPrefs {
  const m = (raw ?? {}) as Record<string, unknown>;
  // Legacy 'cities' mode counts as on; its city list is no longer used.
  const mode: NotifMode = String(m.mode ?? 'all') === 'off' ? 'off' : 'all';
  const types = Array.isArray(m.types)
    ? (m.types as unknown[]).map((t) => String(t))
    : [];
  const countries = Array.isArray(m.countries)
    ? (m.countries as unknown[]).map((c) => String(c).trim().toLowerCase()).filter((c) => c.length > 0)
    : [];
  return { mode, types, countries };
}

function wantsThisEvent(
  prefs: EventNotifPrefs,
  eventType: string,
  eventCountry: string,
): boolean {
  if (prefs.mode === 'off') return false;
  // Empty type list = "All types"; otherwise the event must be tagged with a
  // type the user picked.
  if (prefs.types.length > 0) {
    if (eventType.length === 0) return false;
    if (!prefs.types.includes(eventType)) return false;
  }
  // Empty country list = "All countries"; otherwise the event must be tagged
  // with a country the user picked.
  if (prefs.countries.length > 0) {
    if (eventCountry.length === 0) return false;
    if (!prefs.countries.includes(eventCountry)) return false;
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
 *   `eventNotifPrefs.countries` (needs a composite index) and/or chunk the work
 *   through a task queue.
 * NOTE(country matching): both sides come from the curated `kEventCountries`
 *   list (stored lower-cased on the event as `locationCountry`, picked by the
 *   user as `eventNotifPrefs.countries`), so they match exactly — no free-text
 *   spelling mismatches.
 */
export const onEventCreate = onDocumentCreated('events/{eventId}', async (event) => {
  const eventId = event.params.eventId;
  const data = event.data?.data();
  if (!data) return;

  const title = String(data.title ?? '').trim();
  const location = String(data.location ?? '').trim();
  const eventType = String(data.eventType ?? '').trim();
  const eventCountry = String(data.locationCountry ?? '').trim().toLowerCase();

  const usersSnap = await db.collection('users').get();

  let batch = db.batch();
  let writes = 0;
  let queued = 0;

  for (const userDoc of usersSnap.docs) {
    const u = userDoc.data();
    if (u.suspended === true) continue;
    const prefs = parsePrefs(u.eventNotifPrefs);
    if (!wantsThisEvent(prefs, eventType, eventCountry)) continue;

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
