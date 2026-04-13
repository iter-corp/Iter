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

    const title = data.type === 'message' ? 'New message' : 'New notification';
    const body = `${data.type ?? 'activity'} from ${data.actorUid ?? 'someone'}`;

    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: {
        type: String(data.type ?? ''),
        actorUid: String(data.actorUid ?? ''),
        targetId: String(data.targetId ?? ''),
      },
    });
  },
);
