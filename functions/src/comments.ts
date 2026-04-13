import * as admin from 'firebase-admin';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

const db = admin.firestore();

export const onCommentCreate = onDocumentCreated(
  'posts/{postId}/comments/{commentId}',
  async (event) => {
    const postId = event.params.postId;
    const comment = event.data?.data();
    if (!comment) return;

    const postRef = db.collection('posts').doc(postId);
    const postSnap = await postRef.get();
    const postData = postSnap.data() ?? {};

    const authorUid = String(postData.authorUid ?? '');
    const actorUid = String(comment.authorUid ?? '');

    const batch = db.batch();
    batch.set(postRef, { commentsCount: admin.firestore.FieldValue.increment(1) }, { merge: true });

    if (authorUid.length > 0 && authorUid !== actorUid) {
      const notifRef = db.collection('notifications').doc(authorUid).collection('items').doc();
      batch.set(notifRef, {
        type: 'comment',
        actorUid,
        targetId: postId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  },
);
