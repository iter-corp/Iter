"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onMessageCreate = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const db = admin.firestore();
exports.onMessageCreate = (0, firestore_1.onDocumentCreated)('chats/{chatId}/messages/{messageId}', async (event) => {
    const chatId = event.params.chatId;
    const msg = event.data?.data();
    if (!msg)
        return;
    const senderUid = String(msg.senderUid ?? '');
    const receiverUid = String(msg.receiverUid ?? '');
    const text = String(msg.text ?? '');
    const batch = db.batch();
    batch.set(db.collection('chats').doc(chatId), {
        lastMessage: text,
        lastTime: admin.firestore.FieldValue.serverTimestamp(),
        [`unread.${receiverUid}`]: admin.firestore.FieldValue.increment(1),
    }, { merge: true });
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
