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
exports.onUserDeletedCascadeCleanup = exports.selfDeleteAccount = exports.adminDeleteUser = exports.adminSuspendUser = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const db = admin.firestore();
const auth = admin.auth();
const MAX_BATCH_WRITES = 450;
function getString(value, fieldName) {
    const parsed = String(value ?? '').trim();
    if (parsed.length === 0) {
        throw new https_1.HttpsError('invalid-argument', `${fieldName} is required`);
    }
    return parsed;
}
function getBoolean(value, fieldName) {
    if (typeof value !== 'boolean') {
        throw new https_1.HttpsError('invalid-argument', `${fieldName} must be a boolean`);
    }
    return value;
}
async function requireAdmin(callerUid) {
    const callerSnap = await db.collection('users').doc(callerUid).get();
    const role = callerSnap.data()?.role;
    if (role !== 'admin') {
        throw new https_1.HttpsError('permission-denied', 'Admin access required');
    }
}
async function deletePostsByAuthor(authorUid) {
    let deletedCount = 0;
    while (true) {
        const snap = await db
            .collection('posts')
            .where('authorUid', '==', authorUid)
            .limit(100)
            .get();
        if (snap.empty)
            break;
        for (const postDoc of snap.docs) {
            await db.recursiveDelete(postDoc.ref);
            deletedCount += 1;
        }
    }
    return deletedCount;
}
async function deleteCommentsByAuthor(authorUid) {
    let deletedCount = 0;
    while (true) {
        const snap = await db
            .collectionGroup('comments')
            .where('authorUid', '==', authorUid)
            .limit(200)
            .get();
        if (snap.empty)
            break;
        const postCommentTotals = new Map();
        let batch = db.batch();
        let writes = 0;
        for (const commentDoc of snap.docs) {
            const postRef = commentDoc.ref.parent.parent;
            if (postRef) {
                postCommentTotals.set(postRef.id, (postCommentTotals.get(postRef.id) ?? 0) + 1);
            }
            batch.delete(commentDoc.ref);
            writes += 1;
            deletedCount += 1;
            if (writes >= MAX_BATCH_WRITES) {
                await batch.commit();
                batch = db.batch();
                writes = 0;
            }
        }
        for (const [postId, removedCount] of postCommentTotals.entries()) {
            batch.set(db.collection('posts').doc(postId), { commentsCount: admin.firestore.FieldValue.increment(-removedCount) }, { merge: true });
            writes += 1;
            if (writes >= MAX_BATCH_WRITES) {
                await batch.commit();
                batch = db.batch();
                writes = 0;
            }
        }
        if (writes > 0) {
            await batch.commit();
        }
    }
    return deletedCount;
}
async function deleteDocsByField(collectionPath, field, equals) {
    let deleted = 0;
    while (true) {
        const snap = await db
            .collection(collectionPath)
            .where(field, '==', equals)
            .limit(200)
            .get();
        if (snap.empty)
            break;
        let batch = db.batch();
        let writes = 0;
        for (const doc of snap.docs) {
            batch.delete(doc.ref);
            writes += 1;
            deleted += 1;
            if (writes >= MAX_BATCH_WRITES) {
                await batch.commit();
                batch = db.batch();
                writes = 0;
            }
        }
        if (writes > 0) {
            await batch.commit();
        }
    }
    return deleted;
}
async function cleanupUserData(targetUid) {
    const deletedPosts = await deletePostsByAuthor(targetUid);
    const deletedComments = await deleteCommentsByAuthor(targetUid);
    const deletedStories = await deleteDocsByField('stories', 'authorUid', targetUid);
    const deletedLiveStreams = await deleteDocsByField('liveStreams', 'hostUid', targetUid);
    await db.recursiveDelete(db.collection('notifications').doc(targetUid));
    await db.recursiveDelete(db.collection('feeds').doc(targetUid));
    return {
        deletedPosts,
        deletedComments,
        deletedStories,
        deletedLiveStreams,
    };
}
exports.adminSuspendUser = (0, https_1.onCall)(async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
        throw new https_1.HttpsError('unauthenticated', 'Sign in required');
    }
    await requireAdmin(callerUid);
    const targetUid = getString(request.data?.uid, 'uid');
    const suspended = getBoolean(request.data?.suspended, 'suspended');
    if (targetUid === callerUid && suspended) {
        throw new https_1.HttpsError('failed-precondition', 'Admins cannot suspend themselves');
    }
    const userRef = db.collection('users').doc(targetUid);
    await userRef.set({
        suspended,
        suspendedAt: suspended ? admin.firestore.FieldValue.serverTimestamp() : admin.firestore.FieldValue.delete(),
        suspendedBy: suspended ? callerUid : admin.firestore.FieldValue.delete(),
    }, { merge: true });
    await auth.updateUser(targetUid, { disabled: suspended });
    return {
        uid: targetUid,
        suspended,
    };
});
exports.adminDeleteUser = (0, https_1.onCall)(async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
        throw new https_1.HttpsError('unauthenticated', 'Sign in required');
    }
    await requireAdmin(callerUid);
    const targetUid = getString(request.data?.uid, 'uid');
    if (targetUid === callerUid) {
        throw new https_1.HttpsError('failed-precondition', 'Admins cannot delete themselves');
    }
    const cleanup = await cleanupUserData(targetUid);
    // Mark user as deleted instead of removing document entirely
    await db.collection('users').doc(targetUid).set({
        deleted: true,
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        deletedBy: callerUid,
    }, { merge: true });
    try {
        await auth.deleteUser(targetUid);
    }
    catch (error) {
        const code = error?.code;
        if (code !== 'auth/user-not-found') {
            throw error;
        }
    }
    return {
        uid: targetUid,
        ...cleanup,
    };
});
// App Store requirement: users must be able to delete their own account
// from within the app. This mirrors `adminDeleteUser` but the caller is the
// target — no admin role required.
exports.selfDeleteAccount = (0, https_1.onCall)(async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
        throw new https_1.HttpsError('unauthenticated', 'Sign in required');
    }
    const cleanup = await cleanupUserData(callerUid);
    await db.collection('users').doc(callerUid).set({
        deleted: true,
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        deletedBy: callerUid,
    }, { merge: true });
    try {
        await auth.deleteUser(callerUid);
    }
    catch (error) {
        const code = error?.code;
        if (code !== 'auth/user-not-found') {
            throw error;
        }
    }
    return {
        uid: callerUid,
        ...cleanup,
    };
});
exports.onUserDeletedCascadeCleanup = (0, firestore_1.onDocumentDeleted)('users/{uid}', async (event) => {
    const targetUid = event.params.uid;
    if (!targetUid)
        return;
    await cleanupUserData(targetUid);
    try {
        await auth.deleteUser(targetUid);
    }
    catch (error) {
        const code = error?.code;
        if (code !== 'auth/user-not-found') {
            throw error;
        }
    }
});
