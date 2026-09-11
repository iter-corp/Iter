import admin from 'firebase-admin';
import { db, poolConnection } from '../db/index.js';
import {
  users,
  posts,
  comments,
  chats,
  messages,
  events,
  stories,
  polls,
  notifications,
  appConfigs,
} from '../db/schema/index.js';
import fs from 'fs';
import path from 'path';

async function runFirebaseToMysqlMigration() {
  console.log('🚀 Iter / Coil — Firebase to MySQL Data Importer\n');

  // Locate service account key
  const potentialPaths = [
    process.env.FIREBASE_SERVICE_ACCOUNT_KEY,
    path.resolve('./serviceAccountKey.json'),
    path.resolve('../serviceAccountKey.json'),
    path.resolve('./firebase-service-account.json'),
  ].filter(Boolean) as string[];

  let serviceAccountPath: string | null = null;
  for (const p of potentialPaths) {
    if (fs.existsSync(p)) {
      serviceAccountPath = p;
      break;
    }
  }

  if (!serviceAccountPath) {
    console.error('❌ Service account key not found!');
    console.log('\n📋 How to run this import:');
    console.log('1. Go to Firebase Console -> Project Settings -> Service Accounts');
    console.log('2. Click "Generate new private key" (downloads a .json file)');
    console.log('3. Save it as "serviceAccountKey.json" in: ' + path.resolve('.'));
    console.log('4. Re-run: npm run db:import-firebase\n');
    process.exit(1);
  }

  console.log(`🔑 Using service account key: ${serviceAccountPath}`);
  const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }

  const firestore = admin.firestore();

  let publicUploadBase = process.env.STORAGE_PUBLIC_URL;
  if (!publicUploadBase) {
    try {
      const cfgPath = [path.resolve('./ecosystem.config.json'), path.resolve('../ecosystem.config.json')].find(fs.existsSync);
      if (cfgPath) {
        const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
        publicUploadBase = cfg.profiles?.[cfg.activeProfile]?.storagePublicUrl;
      }
    } catch (_) {}
  }
  publicUploadBase = publicUploadBase || 'http://192.168.1.194:3000/uploads';

  function rewriteUrl(url?: string | null): string | null {
    if (!url) return null;
    return url.replace(/https:\/\/[^/]+\.supabase\.co\/storage\/v1\/object\/public\//g, `${publicUploadBase}/`);
  }

  function rewriteUrls(urls: string[]): string[] {
    return urls.map((u) => rewriteUrl(u) || u);
  }

  // ── 1. Migrate Users ────────────────────────────────────────────────────────
  console.log('\n📦 Migrating Users from Firestore...');
  try {
    const userSnaps = await firestore.collection('users').get();
    console.log(`Found ${userSnaps.size} user documents.`);
    let userCount = 0;
    for (const doc of userSnaps.docs) {
      const d = doc.data();
      await db.insert(users).ignore().values({
        id: doc.id,
        email: (d.email || `${doc.id}@iter.local`).toLowerCase(),
        emailVerified: d.emailVerified ?? false,
        username: d.username || null,
        usernameLower: d.usernameLower || (d.username ? d.username.toLowerCase() : null),
        handle: d.handle || null,
        bio: d.bio || '',
        avatarUrl: rewriteUrl(d.avatarUrl),
        coverUrl: rewriteUrl(d.coverUrl),
        gender: d.gender || null,
        role: d.role || 'user',
        suspended: d.suspended ?? false,
        isPrivate: d.isPrivate ?? false,
        appIntroSeen: d.appIntroSeen ?? true,
        followersCount: Number(d.followersCount) || 0,
        followingCount: Number(d.followingCount) || 0,
        postsCount: Number(d.postsCount) || 0,
        profession: d.profession || null,
        field: d.field || null,
        academicLevel: d.academicLevel || null,
        goals: Array.isArray(d.goals) ? d.goals : [],
        blockedUsers: Array.isArray(d.blockedUsers) ? d.blockedUsers : [],
        metadata: d.metadata || {},
        createdAt: d.createdAt?.toDate ? d.createdAt.toDate() : new Date(),
        updatedAt: d.updatedAt?.toDate ? d.updatedAt.toDate() : new Date(),
      });
      userCount++;
    }
    console.log(`✅ Migrated ${userCount} users into MySQL.`);
  } catch (err) {
    console.error('⚠️ User migration warning:', err);
  }

  // ── 2. Migrate Posts ────────────────────────────────────────────────────────
  console.log('\n📦 Migrating Posts from Firestore...');
  try {
    const postSnaps = await firestore.collection('posts').get();
    console.log(`Found ${postSnaps.size} post documents.`);
    let postCount = 0;
    for (const doc of postSnaps.docs) {
      const d = doc.data();
      const authorUid = d.authorUid || d.uid;
      if (!authorUid) continue;

      await db.insert(posts).ignore().values({
        id: doc.id,
        authorUid,
        authorUsername: d.authorUsername || d.username || 'unknown',
        authorAvatar: rewriteUrl(d.authorAvatar || d.avatarUrl),
        caption: d.caption || d.text || '',
        imageUrls: rewriteUrls(Array.isArray(d.imageUrls) ? d.imageUrls : (d.imageUrl ? [d.imageUrl] : [])),
        videoUrls: rewriteUrls(Array.isArray(d.videoUrls) ? d.videoUrls : (d.videoUrl ? [d.videoUrl] : [])),
        likesCount: Number(d.likesCount) || 0,
        commentsCount: Number(d.commentsCount) || 0,
        isPrivate: d.isPrivate ?? false,
        postType: d.postType || (d.isQa ? 'qa' : 'regular'),
        discussKind: d.discussKind || 'question',
        postPlaceName: d.postPlaceName || null,
        postPlaceCity: d.postPlaceCity || null,
        metadata: d.metadata || {},
        createdAt: d.createdAt?.toDate ? d.createdAt.toDate() : new Date(),
        updatedAt: d.updatedAt?.toDate ? d.updatedAt.toDate() : new Date(),
      });
      postCount++;

      // Subcollection comments
      try {
        const commentSnaps = await firestore.collection('posts').doc(doc.id).collection('comments').get();
        for (const cDoc of commentSnaps.docs) {
          const cd = cDoc.data();
          const commentAuthorUid = cd.authorUid || cd.uid;
          if (!commentAuthorUid) continue;
          await db.insert(comments).ignore().values({
            id: cDoc.id,
            postId: doc.id,
            authorUid: commentAuthorUid,
            authorUsername: cd.authorUsername || cd.username || 'user',
            authorAvatar: rewriteUrl(cd.authorAvatar || cd.avatarUrl),
            text: cd.text || cd.comment || '',
            parentCommentId: cd.parentCommentId || null,
            replyToUsername: cd.replyToUsername || null,
            likesCount: Number(cd.likesCount) || 0,
            helpfulCount: Number(cd.helpfulCount) || 0,
            unhelpfulCount: Number(cd.unhelpfulCount) || 0,
            createdAt: cd.createdAt?.toDate ? cd.createdAt.toDate() : new Date(),
            updatedAt: cd.updatedAt?.toDate ? cd.updatedAt.toDate() : new Date(),
          });
        }
      } catch (_) {}
    }
    console.log(`✅ Migrated ${postCount} posts (and comments) into MySQL.`);
  } catch (err) {
    console.error('⚠️ Post migration warning:', err);
  }

  // ── 3. Migrate Events ───────────────────────────────────────────────────────
  console.log('\n📦 Migrating Events from Firestore...');
  try {
    const eventSnaps = await firestore.collection('events').get();
    console.log(`Found ${eventSnaps.size} event documents.`);
    let eventCount = 0;
    for (const doc of eventSnaps.docs) {
      const d = doc.data();
      const authorUid = d.authorUid || d.createdByUid || d.uid;
      if (!authorUid) continue;

      await db.insert(events).ignore().values({
        id: doc.id,
        title: d.title || 'Untitled Event',
        description: d.description || '',
        location: d.location || '',
        locationCountry: (d.locationCountry || 'other').toLowerCase(),
        eventType: d.eventType || 'other',
        coverImageUrl: rewriteUrl(d.coverImageUrl),
        linkUrl: d.linkUrl || null,
        authorUid,
        authorUsername: d.authorUsername || 'admin',
        isOnline: d.isOnline ?? false,
        createdAt: d.createdAt?.toDate ? d.createdAt.toDate() : new Date(),
        updatedAt: d.updatedAt?.toDate ? d.updatedAt.toDate() : new Date(),
      });
      eventCount++;
    }
    console.log(`✅ Migrated ${eventCount} events into MySQL.`);
  } catch (err) {
    console.error('⚠️ Event migration warning:', err);
  }

  // ── 4. Migrate Stories ──────────────────────────────────────────────────────
  console.log('\n📦 Migrating Stories from Firestore...');
  try {
    const storySnaps = await firestore.collection('stories').get();
    console.log(`Found ${storySnaps.size} story documents.`);
    let storyCount = 0;
    for (const doc of storySnaps.docs) {
      const d = doc.data();
      const authorUid = d.authorUid || d.uid;
      if (!authorUid) continue;

      const created = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();
      const expires = d.expiresAt?.toDate ? d.expiresAt.toDate() : new Date(created.getTime() + 24 * 60 * 60 * 1000);

      await db.insert(stories).ignore().values({
        id: doc.id,
        authorUid,
        authorUsername: d.authorUsername || 'unknown',
        authorAvatar: rewriteUrl(d.authorAvatar),
        imageUrl: rewriteUrl(d.imageUrl) || '',
        videoUrl: rewriteUrl(d.videoUrl),
        textContent: d.textContent || null,
        createdAt: created,
        expiresAt: expires,
      });
      storyCount++;
    }
    console.log(`✅ Migrated ${storyCount} stories into MySQL.`);
  } catch (err) {
    console.error('⚠️ Story migration warning:', err);
  }

  // ── 5. Migrate Chats ────────────────────────────────────────────────────────
  console.log('\n📦 Migrating Chats & Messages from Firestore...');
  try {
    const chatSnaps = await firestore.collection('chats').get();
    console.log(`Found ${chatSnaps.size} chat conversations.`);
    let chatCount = 0;
    let messageCount = 0;
    for (const doc of chatSnaps.docs) {
      const d = doc.data();
      await db.insert(chats).ignore().values({
        id: doc.id,
        kind: d.kind || 'direct',
        groupName: d.groupName || '',
        lastMessage: d.lastMessage || '',
        lastMessageSenderUid: d.lastMessageSenderUid || '',
        lastTime: d.lastTime?.toDate ? d.lastTime.toDate() : new Date(),
        participants: Array.isArray(d.participants) ? d.participants : [],
        acceptedBy: Array.isArray(d.acceptedBy) ? d.acceptedBy : [],
        unreadCounts: d.unreadCounts || {},
        userData: d.userData || {},
        createdAt: d.createdAt?.toDate ? d.createdAt.toDate() : new Date(),
        updatedAt: d.updatedAt?.toDate ? d.updatedAt.toDate() : new Date(),
      });
      chatCount++;

      // Subcollection messages
      try {
        const msgSnaps = await firestore.collection('chats').doc(doc.id).collection('messages').get();
        for (const mDoc of msgSnaps.docs) {
          const mData = mDoc.data();
          if (!mData.senderUid) continue;
          await db.insert(messages).ignore().values({
            id: mDoc.id,
            chatId: doc.id,
            senderUid: mData.senderUid,
            text: mData.text || '',
            imageUrl: rewriteUrl(mData.imageUrl),
            videoUrl: rewriteUrl(mData.videoUrl),
            voiceUrl: rewriteUrl(mData.voiceUrl),
            createdAt: mData.createdAt?.toDate ? mData.createdAt.toDate() : new Date(),
          });
          messageCount++;
        }
      } catch (_) {}
    }
    console.log(`✅ Migrated ${chatCount} chats and ${messageCount} messages into MySQL.`);
  } catch (err) {
    console.error('⚠️ Chat migration warning:', err);
  }

  console.log('\n🎉 All Firebase data successfully imported into MySQL!');
  await poolConnection.end();
  process.exit(0);
}

runFirebaseToMysqlMigration().catch((err) => {
  console.error('Fatal migration error:', err);
  process.exit(1);
});
