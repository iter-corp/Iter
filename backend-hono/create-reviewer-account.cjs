const admin = require('firebase-admin');
const path = require('path');
const sa = require('./serviceAccountKey.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(sa),
  });
}

const auth = admin.auth();
const db = admin.firestore();

async function setupAdminAccount({ uid, email, password, username, displayName, bio }) {
  console.log(`\n========================================`);
  console.log(`Setting up account: ${email} (${uid})`);
  console.log(`========================================`);

  // 1. Firebase Auth
  let authUser;
  try {
    authUser = await auth.getUser(uid);
    console.log(`ℹ️ User found in Firebase Auth by UID: ${uid}`);
    authUser = await auth.updateUser(uid, {
      email,
      emailVerified: true,
      password,
      displayName,
    });
    console.log(`✅ Updated existing Auth user credentials & emailVerified = true`);
  } catch (err) {
    if (err.code === 'auth/user-not-found') {
      try {
        authUser = await auth.getUserByEmail(email);
        console.log(`ℹ️ User found in Firebase Auth by email: ${email} (UID: ${authUser.uid})`);
        authUser = await auth.updateUser(authUser.uid, {
          emailVerified: true,
          password,
          displayName,
        });
        uid = authUser.uid;
        console.log(`✅ Updated existing Auth user credentials`);
      } catch (e2) {
        authUser = await auth.createUser({
          uid,
          email,
          emailVerified: true,
          password,
          displayName,
        });
        console.log(`✅ Created fresh Auth user with UID: ${uid}`);
      }
    } else {
      throw err;
    }
  }

  // 2. Custom Claims
  await auth.setCustomUserClaims(uid, {
    admin: true,
    role: 'admin',
    superadmin: true,
  });
  console.log(`✅ Set custom claims: { admin: true, role: 'admin', superadmin: true }`);

  // 3. Firestore Document
  const userRef = db.collection('users').doc(uid);
  const existingDoc = await userRef.get();

  const docData = {
    uid,
    email,
    username,
    usernameLower: username.toLowerCase(),
    handle: `@${username}`,
    name: displayName,
    bio,
    role: 'admin',
    suspended: false,
    isPrivate: false,
    appIntroSeen: true,
    welcomeMessageSeen: true,
    postsCount: existingDoc.exists ? (existingDoc.data().postsCount || 0) : 0,
    followersCount: existingDoc.exists ? (existingDoc.data().followersCount || 0) : 0,
    followingCount: existingDoc.exists ? (existingDoc.data().followingCount || 0) : 0,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (!existingDoc.exists) {
    docData.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

  await userRef.set(docData, { merge: true });
  console.log(`✅ Firestore doc users/${uid} set with role: 'admin'`);

  return { uid, email, password, role: 'admin' };
}

async function main() {
  try {
    // 1. Dedicated Google Reviewer Account
    const reviewer = await setupAdminAccount({
      uid: 'google_reviewer_admin_2026',
      email: 'google.reviewer@iter.app',
      password: 'IterReview2026!',
      username: 'google.reviewer',
      displayName: 'Google Reviewer',
      bio: 'Official Google Play App Reviewer (Super Admin)',
    });

    // 2. Seed Admin Account
    const seedAdmin = await setupAdminAccount({
      uid: 'admin_initial_root',
      email: 'admin@iter.app',
      password: 'Admin@123456',
      username: 'admin',
      displayName: 'Iter Administrator',
      bio: 'Official Iter System Administrator',
    });

    console.log(`\n🎉 Accounts successfully provisioned!`);
    console.log(`----------------------------------------`);
    console.log(`Reviewer Account:`);
    console.log(`  Email:    ${reviewer.email}`);
    console.log(`  Password: ${reviewer.password}`);
    console.log(`  Role:     ${reviewer.role}`);
    console.log(`----------------------------------------`);
    console.log(`Admin Account:`);
    console.log(`  Email:    ${seedAdmin.email}`);
    console.log(`  Password: ${seedAdmin.password}`);
    console.log(`  Role:     ${seedAdmin.role}`);
    console.log(`========================================\n`);

    process.exit(0);
  } catch (err) {
    console.error(`❌ Provisioning failed:`, err);
    process.exit(1);
  }
}

main();
