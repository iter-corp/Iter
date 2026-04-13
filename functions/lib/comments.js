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
exports.onCommentCreate = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const db = admin.firestore();
exports.onCommentCreate = (0, firestore_1.onDocumentCreated)('posts/{postId}/comments/{commentId}', async (event) => {
    const postId = event.params.postId;
    const comment = event.data?.data();
    if (!comment)
        return;
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
});
