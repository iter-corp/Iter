import * as admin from 'firebase-admin';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

const db = admin.firestore();

export const onMessageCreate = onDocumentCreated('chats/{chatId}/messages/{messageId}', async (event) => {
  const chatId = event.params.chatId;
  const msg = event.data?.data();
  if (!msg) return;

  const senderUid = String(msg.senderUid ?? '');
  const receiverUid = String(msg.receiverUid ?? '');
  const text = String(msg.text ?? '');

  const batch = db.batch();

  batch.set(
    db.collection('chats').doc(chatId),
    {
      lastMessage: text,
      lastTime: admin.firestore.FieldValue.serverTimestamp(),
      [`unread.${receiverUid}`]: admin.firestore.FieldValue.increment(1),
    },
    { merge: true },
  );

  const notifRef = db.collection('notifications').doc(receiverUid).collection('items').doc();
  batch.set(notifRef, {
    type: 'message',
    actorUid: senderUid,
    targetId: chatId,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
});
