import * as admin from 'firebase-admin';
import { onDocumentCreated, onDocumentDeleted } from 'firebase-functions/v2/firestore';

const db = admin.firestore();

export const onFollowCreate = onDocumentCreated('follows/{targetUid}/followers/{followerUid}', async (event) => {
  const targetUid = event.params.targetUid;
  const followerUid = event.params.followerUid;

  const batch = db.batch();

  batch.set(
    db.collection('users').doc(targetUid),
    { followersCount: admin.firestore.FieldValue.increment(1) },
    { merge: true },
  );
  batch.set(
    db.collection('users').doc(followerUid),
    { followingCount: admin.firestore.FieldValue.increment(1) },
    { merge: true },
  );

  const notifRef = db.collection('notifications').doc(targetUid).collection('items').doc();
  batch.set(notifRef, {
    type: 'follow',
    actorUid: followerUid,
    targetId: followerUid,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
});

export const onFollowDelete = onDocumentDeleted('follows/{targetUid}/followers/{followerUid}', async (event) => {
  const targetUid = event.params.targetUid;
  const followerUid = event.params.followerUid;

  const batch = db.batch();
  batch.set(
    db.collection('users').doc(targetUid),
    { followersCount: admin.firestore.FieldValue.increment(-1) },
    { merge: true },
  );
  batch.set(
    db.collection('users').doc(followerUid),
    { followingCount: admin.firestore.FieldValue.increment(-1) },
    { merge: true },
  );
  await batch.commit();
});
