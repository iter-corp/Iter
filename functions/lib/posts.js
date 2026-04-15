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
exports.onPostCreate = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const db = admin.firestore();
const MAX_BATCH_WRITES = 450;
exports.onPostCreate = (0, firestore_1.onDocumentCreated)('posts/{postId}', async (event) => {
    const postId = event.params.postId;
    const post = event.data?.data();
    if (!post)
        return;
    const authorUid = String(post.authorUid ?? '').trim();
    if (authorUid.length === 0)
        return;
    const isPrivate = Boolean(post.isPrivate);
    const followersSnap = await db
        .collection('users')
        .doc(authorUid)
        .collection('followers')
        .get();
    const targetUids = new Set([authorUid]);
    if (!isPrivate) {
        for (const follower of followersSnap.docs) {
            targetUids.add(follower.id);
        }
    }
    const createdAt = post.createdAt ?? admin.firestore.FieldValue.serverTimestamp();
    let batch = db.batch();
    let writes = 0;
    for (const uid of targetUids) {
        const timelineRef = db.collection('feeds').doc(uid).collection('timeline').doc(postId);
        batch.set(timelineRef, {
            postId,
            authorUid,
            createdAt,
        }, { merge: true });
        writes++;
        if (writes >= MAX_BATCH_WRITES) {
            await batch.commit();
            batch = db.batch();
            writes = 0;
        }
    }
    if (writes > 0) {
        await batch.commit();
    }
});
