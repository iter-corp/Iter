import * as admin from 'firebase-admin';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

const db = admin.firestore();

/**
 * When a user likes a post, create a notification for the post author.
 * Skips if the liker IS the post author (no self-notification).
 */
export const onLikeCreate = onDocumentCreated(
  'posts/{postId}/likes/{likerUid}',
  async (event) => {
    const postId = event.params.postId;
    const likerUid = event.params.likerUid;

    // Look up the post to find the author.
    const postSnap = await db.collection('posts').doc(postId).get();
    const postData = postSnap.data();
    if (!postData) return;

    const authorUid = String(postData.authorUid ?? '');
    // Don't notify yourself.
    if (!authorUid || authorUid === likerUid) return;

    await db
      .collection('notifications')
      .doc(authorUid)
      .collection('items')
      .add({
        type: 'like',
        actorUid: likerUid,
        targetId: postId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  },
);
