import * as admin from 'firebase-admin';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

const db = admin.firestore();

export const onMessageCreate = onDocumentCreated('chats/{chatId}/messages/{messageId}', async (event) => {
  const chatId = event.params.chatId;
  const msg = event.data?.data();
  if (!msg) return;

  const senderUid = String(msg.senderUid ?? '');
  let receiverUid = String(msg.receiverUid ?? '');

  if (receiverUid.length === 0) {
    const chatSnap = await db.collection('chats').doc(chatId).get();
    const participants = (chatSnap.data()?.participants as string[] | undefined) ?? [];
    receiverUid = participants.find((uid) => uid !== senderUid) ?? '';
  }

  if (receiverUid.length === 0) return;

  const text = String(msg.text ?? '').trim();
  const imageUrl = String(msg.imageUrl ?? '').trim();
  const lastMessage = text.length > 0 ? text : (imageUrl.length > 0 ? 'Photo' : 'Message');

  const batch = db.batch();

  const chatRef = db.collection('chats').doc(chatId);
  batch.set(
    chatRef,
    {
      lastMessage,
      lastMessageSenderUid: senderUid,
      lastTime: admin.firestore.FieldValue.serverTimestamp(),
      [`unread.${receiverUid}`]: admin.firestore.FieldValue.increment(1),
      [`unread.${senderUid}`]: 0,
      acceptedBy: admin.firestore.FieldValue.arrayUnion(senderUid),
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
