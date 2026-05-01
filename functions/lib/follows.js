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
exports.onFollowDelete = exports.onFollowUpdate = exports.onFollowCreate = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const db = admin.firestore();
function isPendingFollow(data) {
    return data?.status === 'pending';
}
function followNotificationId(followerUid) {
    return `follow_${followerUid}`;
}
function followRequestNotificationId(followerUid) {
    return `follow_request_${followerUid}`;
}
exports.onFollowCreate = (0, firestore_1.onDocumentCreated)('users/{targetUid}/followers/{followerUid}', async (event) => {
    const targetUid = event.params.targetUid;
    const followerUid = event.params.followerUid;
    const data = event.data?.data();
    const pending = isPendingFollow(data);
    const batch = db.batch();
    if (!pending) {
        batch.set(db.collection('users').doc(targetUid), { followersCount: admin.firestore.FieldValue.increment(1) }, { merge: true });
        batch.set(db.collection('users').doc(followerUid), { followingCount: admin.firestore.FieldValue.increment(1) }, { merge: true });
    }
    const notifRef = db
        .collection('notifications')
        .doc(targetUid)
        .collection('items')
        .doc(pending ? followRequestNotificationId(followerUid) : followNotificationId(followerUid));
    batch.set(notifRef, {
        type: pending ? 'follow_request' : 'follow',
        actorUid: followerUid,
        targetId: followerUid,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();
});
exports.onFollowUpdate = (0, firestore_1.onDocumentUpdated)('users/{targetUid}/followers/{followerUid}', async (event) => {
    const targetUid = event.params.targetUid;
    const followerUid = event.params.followerUid;
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const wasPending = isPendingFollow(before);
    const isPending = isPendingFollow(after);
    if (wasPending === isPending) {
        return;
    }
    const batch = db.batch();
    if (wasPending && !isPending) {
        batch.set(db.collection('users').doc(targetUid), { followersCount: admin.firestore.FieldValue.increment(1) }, { merge: true });
        batch.set(db.collection('users').doc(followerUid), { followingCount: admin.firestore.FieldValue.increment(1) }, { merge: true });
        batch.delete(db.collection('notifications')
            .doc(targetUid)
            .collection('items')
            .doc(followRequestNotificationId(followerUid)));
    }
    if (!wasPending && isPending) {
        batch.set(db.collection('users').doc(targetUid), { followersCount: admin.firestore.FieldValue.increment(-1) }, { merge: true });
        batch.set(db.collection('users').doc(followerUid), { followingCount: admin.firestore.FieldValue.increment(-1) }, { merge: true });
        batch.set(db.collection('notifications')
            .doc(targetUid)
            .collection('items')
            .doc(followRequestNotificationId(followerUid)), {
            type: 'follow_request',
            actorUid: followerUid,
            targetId: followerUid,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    await batch.commit();
});
exports.onFollowDelete = (0, firestore_1.onDocumentDeleted)('users/{targetUid}/followers/{followerUid}', async (event) => {
    const targetUid = event.params.targetUid;
    const followerUid = event.params.followerUid;
    const data = event.data?.data();
    const pending = isPendingFollow(data);
    const batch = db.batch();
    if (!pending) {
        batch.set(db.collection('users').doc(targetUid), { followersCount: admin.firestore.FieldValue.increment(-1) }, { merge: true });
        batch.set(db.collection('users').doc(followerUid), { followingCount: admin.firestore.FieldValue.increment(-1) }, { merge: true });
    }
    batch.delete(db.collection('notifications')
        .doc(targetUid)
        .collection('items')
        .doc(pending ? followRequestNotificationId(followerUid) : followNotificationId(followerUid)));
    await batch.commit();
});
