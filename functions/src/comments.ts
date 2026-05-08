import * as admin from 'firebase-admin';
import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';

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
    const postType = String(postData.postType ?? '');

    const authorUid = String(postData.authorUid ?? '');
    const actorUid = String(comment.authorUid ?? '');
    const parentCommentId = String(comment.parentCommentId ?? '');

    const batch = db.batch();
    batch.set(postRef, { commentsCount: admin.firestore.FieldValue.increment(1) }, { merge: true });

    if (postType === 'qa') {
      if (parentCommentId.length === 0) {
        if (authorUid.length > 0 && authorUid !== actorUid) {
          const notifRef = db
            .collection('notifications')
            .doc(authorUid)
            .collection('items')
            .doc(`qa_answer_${postId}_${event.params.commentId}_${actorUid}`);
          batch.set(
            notifRef,
            {
              type: 'qa_answer',
              actorUid,
              targetId: postId,
              commentId: event.params.commentId,
              read: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
      } else {
        const parentSnap = await db.collection('posts').doc(postId).collection('comments').doc(parentCommentId).get();
        const parentAuthorUid = String(parentSnap.data()?.authorUid ?? '');
        if (parentAuthorUid.length > 0 && parentAuthorUid !== actorUid) {
          const notifRef = db
            .collection('notifications')
            .doc(parentAuthorUid)
            .collection('items')
            .doc(`qa_reply_${postId}_${event.params.commentId}_${actorUid}`);
          batch.set(
            notifRef,
            {
              type: 'qa_reply',
              actorUid,
              targetId: postId,
              commentId: event.params.commentId,
              read: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
      }
    } else if (authorUid.length > 0 && authorUid !== actorUid) {
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

export const onQaAnswerReactionWrite = onDocumentWritten(
  'posts/{postId}/comments/{commentId}/reactions/{reactorUid}',
  async (event) => {
    const postId = event.params.postId;
    const commentId = event.params.commentId;
    const reactorUid = event.params.reactorUid;

    const before = event.data?.before.data() ?? null;
    const after = event.data?.after.data() ?? null;

    const previousType = String(before?.type ?? '');
    const nextType = String(after?.type ?? '');
    if (previousType === nextType) return;

    const [postSnap, commentSnap] = await Promise.all([
      db.collection('posts').doc(postId).get(),
      db.collection('posts').doc(postId).collection('comments').doc(commentId).get(),
    ]);
    const postData = postSnap.data() ?? {};
    if (String(postData.postType ?? '') !== 'qa') return;

    const commentAuthorUid = String(commentSnap.data()?.authorUid ?? '');
    if (commentAuthorUid.length === 0 || commentAuthorUid === reactorUid) return;

    const notifCol = db.collection('notifications').doc(commentAuthorUid).collection('items');
    const likeNotifId = `qa_answer_like_${postId}_${commentId}_${reactorUid}`;
    const dislikeNotifId = `qa_answer_dislike_${postId}_${commentId}_${reactorUid}`;

    const batch = db.batch();

    if (previousType === 'heart') {
      batch.delete(notifCol.doc(likeNotifId));
    }
    if (previousType === 'broken') {
      batch.delete(notifCol.doc(dislikeNotifId));
    }

    if (nextType === 'heart' || nextType === 'broken') {
      const notifId = nextType === 'heart' ? likeNotifId : dislikeNotifId;
      const notifType = nextType === 'heart' ? 'qa_answer_like' : 'qa_answer_dislike';
      batch.set(
        notifCol.doc(notifId),
        {
          type: notifType,
          actorUid: reactorUid,
          targetId: postId,
          commentId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    await batch.commit();
  },
);
