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
exports.onLikeCreate = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const db = admin.firestore();
/**
 * When a user likes a post, create a notification for the post author.
 * Skips if the liker IS the post author (no self-notification).
 */
exports.onLikeCreate = (0, firestore_1.onDocumentCreated)('posts/{postId}/likes/{likerUid}', async (event) => {
    const postId = event.params.postId;
    const likerUid = event.params.likerUid;
    // Look up the post to find the author.
    const postSnap = await db.collection('posts').doc(postId).get();
    const postData = postSnap.data();
    if (!postData)
        return;
    const authorUid = String(postData.authorUid ?? '');
    // Don't notify yourself.
    if (!authorUid || authorUid === likerUid)
        return;
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
});
