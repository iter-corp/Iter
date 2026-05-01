import * as admin from 'firebase-admin';
import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} from 'firebase-functions/v2/firestore';

const db = admin.firestore();

function isPendingFollow(data: FirebaseFirestore.DocumentData | undefined): boolean {
  return data?.status === 'pending';
}

function followNotificationId(followerUid: string): string {
  return `follow_${followerUid}`;
}

function followRequestNotificationId(followerUid: string): string {
  return `follow_request_${followerUid}`;
}

export const onFollowCreate = onDocumentCreated('users/{targetUid}/followers/{followerUid}', async (event) => {
  const targetUid = event.params.targetUid;
  const followerUid = event.params.followerUid;
  const data = event.data?.data();
  const pending = isPendingFollow(data);

  const batch = db.batch();

  if (!pending) {
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
  }

  const notifRef = db
    .collection('notifications')
    .doc(targetUid)
    .collection('items')
    .doc(pending ? followRequestNotificationId(followerUid) : followNotificationId(followerUid));
  batch.set(notifRef, {
    type: pending ? 'follow_request' : 'follow',
    actorUid: followerUid,
    targetId: followerUid,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
});

export const onFollowUpdate = onDocumentUpdated('users/{targetUid}/followers/{followerUid}', async (event) => {
  const targetUid = event.params.targetUid;
  const followerUid = event.params.followerUid;

  const before = event.data?.before.data();
  const after = event.data?.after.data();

  const wasPending = isPendingFollow(before);
  const isPending = isPendingFollow(after);

  if (wasPending === isPending) {
    return;
  }

  const batch = db.batch();

  if (wasPending && !isPending) {
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
    batch.delete(
      db.collection('notifications')
        .doc(targetUid)
        .collection('items')
        .doc(followRequestNotificationId(followerUid)),
    );
  }

  if (!wasPending && isPending) {
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
    batch.set(
      db.collection('notifications')
        .doc(targetUid)
        .collection('items')
        .doc(followRequestNotificationId(followerUid)),
      {
        type: 'follow_request',
        actorUid: followerUid,
        targetId: followerUid,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    );
  }

  await batch.commit();
});

export const onFollowDelete = onDocumentDeleted('users/{targetUid}/followers/{followerUid}', async (event) => {
  const targetUid = event.params.targetUid;
  const followerUid = event.params.followerUid;
  const data = event.data?.data();
  const pending = isPendingFollow(data);

  const batch = db.batch();
  if (!pending) {
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
  }
  batch.delete(
    db.collection('notifications')
      .doc(targetUid)
      .collection('items')
      .doc(pending ? followRequestNotificationId(followerUid) : followNotificationId(followerUid)),
  );
  await batch.commit();
});
