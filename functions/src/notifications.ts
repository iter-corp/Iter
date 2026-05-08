import * as admin from 'firebase-admin';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

const db = admin.firestore();

export const sendPushOnNotificationCreate = onDocumentCreated(
  'notifications/{uid}/items/{notificationId}',
  async (event) => {
    const uid = event.params.uid;
    const data = event.data?.data();
    if (!data) return;

    const userSnap = await db.collection('users').doc(uid).get();
    const userData = userSnap.data() ?? {};
    const tokens = ((userData.fcmTokens as string[] | undefined) ?? []).filter((t) => t.length > 0);

    if (tokens.length === 0) return;

    // Resolve actor username for a human-readable push body.
    const actorUid = String(data.actorUid ?? '');
    let actorName = 'Someone';
    if (actorUid.length > 0) {
      const actorSnap = await db.collection('users').doc(actorUid).get();
      actorName = (actorSnap.data()?.username as string) || actorName;
    }

    let title: string;
    let body: string;
    switch (data.type) {
      case 'follow':
        title = 'New follower';
        body = `${actorName} started following you`;
        break;
      case 'like':
        title = 'New like';
        body = `${actorName} liked your post`;
        break;
      case 'qa_answer_like':
        title = 'New like';
        body = `${actorName} liked your answer`;
        break;
      case 'qa_answer_dislike':
        title = 'New reaction';
        body = `${actorName} disliked your answer`;
        break;
      case 'comment':
        title = 'New comment';
        body = `${actorName} commented on your post`;
        break;
      case 'qa_answer':
        title = 'New answer';
        body = `${actorName} answered your question`;
        break;
      case 'qa_reply':
      case 'reply':
        title = 'New reply';
        body = `${actorName} replied to you`;
        break;
      case 'message':
        title = 'New message';
        body = `${actorName} sent you a message`;
        break;
      default:
        title = 'COIL';
        body = `${actorName} interacted with you`;
    }

    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: {
        type: String(data.type ?? ''),
        actorUid,
        targetId: String(data.targetId ?? ''),
      },
    });
  },
);
