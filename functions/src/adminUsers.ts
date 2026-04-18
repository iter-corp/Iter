import * as admin from 'firebase-admin';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onDocumentDeleted } from 'firebase-functions/v2/firestore';

const db = admin.firestore();
const auth = admin.auth();
const MAX_BATCH_WRITES = 450;

function getString(value: unknown, fieldName: string): string {
  const parsed = String(value ?? '').trim();
  if (parsed.length === 0) {
    throw new HttpsError('invalid-argument', `${fieldName} is required`);
  }
  return parsed;
}

function getBoolean(value: unknown, fieldName: string): boolean {
  if (typeof value !== 'boolean') {
    throw new HttpsError('invalid-argument', `${fieldName} must be a boolean`);
  }
  return value;
}

async function requireAdmin(callerUid: string): Promise<void> {
  const callerSnap = await db.collection('users').doc(callerUid).get();
  const role = callerSnap.data()?.role;
  if (role !== 'admin') {
    throw new HttpsError('permission-denied', 'Admin access required');
  }
}

async function deletePostsByAuthor(authorUid: string): Promise<number> {
  let deletedCount = 0;
  while (true) {
    const snap = await db
      .collection('posts')
      .where('authorUid', '==', authorUid)
      .limit(100)
      .get();

    if (snap.empty) break;

    for (const postDoc of snap.docs) {
      await db.recursiveDelete(postDoc.ref);
      deletedCount += 1;
    }
  }
  return deletedCount;
}

async function deleteCommentsByAuthor(authorUid: string): Promise<number> {
  let deletedCount = 0;

  while (true) {
    const snap = await db
      .collectionGroup('comments')
      .where('authorUid', '==', authorUid)
      .limit(200)
      .get();

    if (snap.empty) break;

    const postCommentTotals = new Map<string, number>();
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
      batch.set(
        db.collection('posts').doc(postId),
        { commentsCount: admin.firestore.FieldValue.increment(-removedCount) },
        { merge: true },
      );
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

async function deleteDocsByField(
  collectionPath: string,
  field: string,
  equals: string,
): Promise<number> {
  let deleted = 0;
  while (true) {
    const snap = await db
      .collection(collectionPath)
      .where(field, '==', equals)
      .limit(200)
      .get();

    if (snap.empty) break;

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

async function cleanupUserData(targetUid: string): Promise<{
  deletedPosts: number;
  deletedComments: number;
  deletedStories: number;
  deletedLiveStreams: number;
}> {
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

export const adminSuspendUser = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'Sign in required');
  }
  await requireAdmin(callerUid);

  const targetUid = getString(request.data?.uid, 'uid');
  const suspended = getBoolean(request.data?.suspended, 'suspended');

  if (targetUid === callerUid && suspended) {
    throw new HttpsError('failed-precondition', 'Admins cannot suspend themselves');
  }

  const userRef = db.collection('users').doc(targetUid);
  await userRef.set(
    {
      suspended,
      suspendedAt: suspended ? admin.firestore.FieldValue.serverTimestamp() : admin.firestore.FieldValue.delete(),
      suspendedBy: suspended ? callerUid : admin.firestore.FieldValue.delete(),
    },
    { merge: true },
  );

  await auth.updateUser(targetUid, { disabled: suspended });

  return {
    uid: targetUid,
    suspended,
  };
});

export const adminDeleteUser = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'Sign in required');
  }
  await requireAdmin(callerUid);

  const targetUid = getString(request.data?.uid, 'uid');
  if (targetUid === callerUid) {
    throw new HttpsError('failed-precondition', 'Admins cannot delete themselves');
  }

  const cleanup = await cleanupUserData(targetUid);
  
  // Mark user as deleted instead of removing document entirely
  await db.collection('users').doc(targetUid).set(
    {
      deleted: true,
      deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      deletedBy: callerUid,
    },
    { merge: true },
  );

  try {
    await auth.deleteUser(targetUid);
  } catch (error: unknown) {
    const code = (error as { code?: string } | undefined)?.code;
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
export const selfDeleteAccount = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'Sign in required');
  }

  const cleanup = await cleanupUserData(callerUid);

  await db.collection('users').doc(callerUid).set(
    {
      deleted: true,
      deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      deletedBy: callerUid,
    },
    { merge: true },
  );

  try {
    await auth.deleteUser(callerUid);
  } catch (error: unknown) {
    const code = (error as { code?: string } | undefined)?.code;
    if (code !== 'auth/user-not-found') {
      throw error;
    }
  }

  return {
    uid: callerUid,
    ...cleanup,
  };
});

export const onUserDeletedCascadeCleanup = onDocumentDeleted('users/{uid}', async (event) => {
  const targetUid = event.params.uid;
  if (!targetUid) return;

  await cleanupUserData(targetUid);

  try {
    await auth.deleteUser(targetUid);
  } catch (error: unknown) {
    const code = (error as { code?: string } | undefined)?.code;
    if (code !== 'auth/user-not-found') {
      throw error;
    }
  }
});
