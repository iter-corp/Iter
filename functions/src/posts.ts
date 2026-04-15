import * as admin from 'firebase-admin';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

const db = admin.firestore();

const MAX_BATCH_WRITES = 450;

export const onPostCreate = onDocumentCreated('posts/{postId}', async (event) => {
  const postId = event.params.postId;
  const post = event.data?.data();
  if (!post) return;

  const authorUid = String(post.authorUid ?? '').trim();
  if (authorUid.length === 0) return;

  const isPrivate = Boolean(post.isPrivate);

  const followersSnap = await db
    .collection('users')
    .doc(authorUid)
    .collection('followers')
    .get();

  const targetUids = new Set<string>([authorUid]);
  if (!isPrivate) {
    for (const follower of followersSnap.docs) {
      targetUids.add(follower.id);
    }
  }

  const createdAt = post.createdAt ?? admin.firestore.FieldValue.serverTimestamp();

  let batch = db.batch();
  let writes = 0;

  for (const uid of targetUids) {
    const timelineRef = db.collection('feeds').doc(uid).collection('timeline').doc(postId);
    batch.set(
      timelineRef,
      {
        postId,
        authorUid,
        createdAt,
      },
      { merge: true },
    );
    writes++;

    if (writes >= MAX_BATCH_WRITES) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }

  if (writes > 0) {
    await batch.commit();
  }
});
