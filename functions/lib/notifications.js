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
exports.sendPushOnNotificationCreate = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const db = admin.firestore();
exports.sendPushOnNotificationCreate = (0, firestore_1.onDocumentCreated)('notifications/{uid}/items/{notificationId}', async (event) => {
    const uid = event.params.uid;
    const data = event.data?.data();
    if (!data)
        return;
    const userSnap = await db.collection('users').doc(uid).get();
    const userData = userSnap.data() ?? {};
    const tokens = (userData.fcmTokens ?? []).filter((t) => t.length > 0);
    if (tokens.length === 0)
        return;
    // Resolve actor username for a human-readable push body.
    const actorUid = String(data.actorUid ?? '');
    let actorName = 'Someone';
    if (actorUid.length > 0) {
        const actorSnap = await db.collection('users').doc(actorUid).get();
        actorName = actorSnap.data()?.username || actorName;
    }
    let title;
    let body;
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
        case 'new_event': {
            const eventTitle = String(data.title ?? '').trim();
            const eventLoc = String(data.subtitle ?? '').trim();
            title = 'New event';
            body = eventTitle.length > 0
                ? (eventLoc.length > 0 ? `${eventTitle} — ${eventLoc}` : eventTitle)
                : 'A new event was just published';
            break;
        }
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
});
