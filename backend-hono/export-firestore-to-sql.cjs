const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

async function exportFirestoreToSql() {
  console.log('🚀 Exporting Firestore data to SQL...');

  const saPath = path.join(__dirname, 'serviceAccountKey.json');
  if (!fs.existsSync(saPath)) {
    console.error('❌ serviceAccountKey.json not found in backend-hono!');
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
  }

  const db = admin.firestore();
  const sqlStatements = [];

  function escapeSql(val) {
    if (val === null || val === undefined) return 'NULL';
    if (typeof val === 'boolean') return val ? '1' : '0';
    if (typeof val === 'number') return isNaN(val) ? 'NULL' : String(val);
    if (val instanceof Date) return `'${val.toISOString().slice(0, 19).replace('T', ' ')}'`;
    if (typeof val === 'object') return `'${JSON.stringify(val).replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
    return `'${String(val).replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
  }

  sqlStatements.push('-- Iter / Coil Firebase to MySQL Data Export');
  sqlStatements.push('SET FOREIGN_KEY_CHECKS = 0;');

  // 1. Users
  console.log('Reading users...');
  const userDocs = await db.collection('users').get();
  console.log(`Found ${userDocs.size} users`);
  for (const doc of userDocs.docs) {
    const d = doc.data();
    const id = doc.id;
    const email = (d.email || `${id}@iter.local`).toLowerCase();
    const emailVerified = d.emailVerified ? 1 : 0;
    const username = d.username || null;
    const usernameLower = d.usernameLower || (username ? username.toLowerCase() : null);
    const handle = d.handle || null;
    const bio = d.bio || '';
    const avatarUrl = d.avatarUrl || null;
    const coverUrl = d.coverUrl || null;
    const gender = d.gender || null;
    const role = d.role || 'user';
    const isPrivate = d.isPrivate ? 1 : 0;
    const appIntroSeen = d.appIntroSeen !== false ? 1 : 0;
    const followersCount = Number(d.followersCount) || 0;
    const followingCount = Number(d.followingCount) || 0;
    const postsCount = Number(d.postsCount) || 0;
    const profession = d.profession || null;
    const field = d.field || null;
    const academicLevel = d.academicLevel || null;
    const goals = JSON.stringify(Array.isArray(d.goals) ? d.goals : []);
    const blockedUsers = JSON.stringify(Array.isArray(d.blockedUsers) ? d.blockedUsers : []);
    const metadata = JSON.stringify(d.metadata || {});
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();
    const updatedAt = d.updatedAt?.toDate ? d.updatedAt.toDate() : new Date();

    sqlStatements.push(`INSERT IGNORE INTO \`users\` (\`id\`, \`email\`, \`email_verified\`, \`username\`, \`username_lower\`, \`handle\`, \`bio\`, \`avatar_url\`, \`cover_url\`, \`gender\`, \`role\`, \`is_private\`, \`app_intro_seen\`, \`followers_count\`, \`following_count\`, \`posts_count\`, \`profession\`, \`field\`, \`academic_level\`, \`goals\`, \`blocked_users\`, \`metadata\`, \`created_at\`, \`updated_at\`) VALUES (${escapeSql(id)}, ${escapeSql(email)}, ${emailVerified}, ${escapeSql(username)}, ${escapeSql(usernameLower)}, ${escapeSql(handle)}, ${escapeSql(bio)}, ${escapeSql(avatarUrl)}, ${escapeSql(coverUrl)}, ${escapeSql(gender)}, ${escapeSql(role)}, ${isPrivate}, ${appIntroSeen}, ${followersCount}, ${followingCount}, ${postsCount}, ${escapeSql(profession)}, ${escapeSql(field)}, ${escapeSql(academicLevel)}, ${escapeSql(goals)}, ${escapeSql(blockedUsers)}, ${escapeSql(metadata)}, ${escapeSql(createdAt)}, ${escapeSql(updatedAt)});`);
  }

  // 2. Posts & Comments
  console.log('Reading posts...');
  const postDocs = await db.collection('posts').get();
  console.log(`Found ${postDocs.size} posts`);
  for (const doc of postDocs.docs) {
    const d = doc.data();
    const authorUid = d.authorUid || d.uid;
    if (!authorUid) continue;

    const id = doc.id;
    const authorUsername = d.authorUsername || d.username || 'unknown';
    const authorAvatar = d.authorAvatar || d.avatarUrl || null;
    const caption = d.caption || d.text || '';
    const imageUrls = JSON.stringify(Array.isArray(d.imageUrls) ? d.imageUrls : (d.imageUrl ? [d.imageUrl] : []));
    const videoUrls = JSON.stringify(Array.isArray(d.videoUrls) ? d.videoUrls : (d.videoUrl ? [d.videoUrl] : []));
    const likesCount = Number(d.likesCount) || 0;
    const commentsCount = Number(d.commentsCount) || 0;
    const isPrivate = d.isPrivate ? 1 : 0;
    const postType = d.postType || (d.isQa ? 'qa' : 'regular');
    const discussKind = d.discussKind || 'question';
    const postPlaceName = d.postPlaceName || null;
    const postPlaceCity = d.postPlaceCity || null;
    const metadata = JSON.stringify(d.metadata || {});
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();
    const updatedAt = d.updatedAt?.toDate ? d.updatedAt.toDate() : new Date();

    sqlStatements.push(`INSERT IGNORE INTO \`posts\` (\`id\`, \`author_uid\`, \`author_username\`, \`author_avatar\`, \`caption\`, \`image_urls\`, \`video_urls\`, \`likes_count\`, \`comments_count\`, \`is_private\`, \`post_type\`, \`discuss_kind\`, \`post_place_name\`, \`post_place_city\`, \`metadata\`, \`created_at\`, \`updated_at\`) VALUES (${escapeSql(id)}, ${escapeSql(authorUid)}, ${escapeSql(authorUsername)}, ${escapeSql(authorAvatar)}, ${escapeSql(caption)}, ${escapeSql(imageUrls)}, ${escapeSql(videoUrls)}, ${likesCount}, ${commentsCount}, ${isPrivate}, ${escapeSql(postType)}, ${escapeSql(discussKind)}, ${escapeSql(postPlaceName)}, ${escapeSql(postPlaceCity)}, ${escapeSql(metadata)}, ${escapeSql(createdAt)}, ${escapeSql(updatedAt)});`);

    // Comments subcollection
    const commentDocs = await db.collection('posts').doc(id).collection('comments').get();
    for (const cDoc of commentDocs.docs) {
      const cd = cDoc.data();
      const cAuthorUid = cd.authorUid || cd.uid;
      if (!cAuthorUid) continue;

      const cId = cDoc.id;
      const cText = cd.text || cd.comment || '';
      const cAuthorUsername = cd.authorUsername || cd.username || 'user';
      const cAuthorAvatar = cd.authorAvatar || cd.avatarUrl || null;
      const cParentId = cd.parentCommentId || null;
      const cReplyTo = cd.replyToUsername || null;
      const cLikes = Number(cd.likesCount) || 0;
      const cHelpful = Number(cd.helpfulCount) || 0;
      const cUnhelpful = Number(cd.unhelpfulCount) || 0;
      const cCreatedAt = cd.createdAt?.toDate ? cd.createdAt.toDate() : new Date();
      const cUpdatedAt = cd.updatedAt?.toDate ? cd.updatedAt.toDate() : new Date();

      sqlStatements.push(`INSERT IGNORE INTO \`comments\` (\`id\`, \`post_id\`, \`author_uid\`, \`author_username\`, \`author_avatar\`, \`text\`, \`parent_comment_id\`, \`reply_to_username\`, \`likes_count\`, \`helpful_count\`, \`unhelpful_count\`, \`created_at\`, \`updated_at\`) VALUES (${escapeSql(cId)}, ${escapeSql(id)}, ${escapeSql(cAuthorUid)}, ${escapeSql(cAuthorUsername)}, ${escapeSql(cAuthorAvatar)}, ${escapeSql(cText)}, ${escapeSql(cParentId)}, ${escapeSql(cReplyTo)}, ${cLikes}, ${cHelpful}, ${cUnhelpful}, ${escapeSql(cCreatedAt)}, ${escapeSql(cUpdatedAt)});`);
    }
  }

  // 3. Events
  console.log('Reading events...');
  const eventDocs = await db.collection('events').get();
  console.log(`Found ${eventDocs.size} events`);
  for (const doc of eventDocs.docs) {
    const d = doc.data();
    const authorUid = d.authorUid || d.createdByUid || d.uid;
    if (!authorUid) continue;

    const id = doc.id;
    const title = d.title || 'Untitled Event';
    const description = d.description || '';
    const location = d.location || '';
    const locationCountry = (d.locationCountry || 'other').toLowerCase();
    const eventType = d.eventType || 'other';
    const coverImageUrl = d.coverImageUrl || null;
    const linkUrl = d.linkUrl || null;
    const authorUsername = d.authorUsername || 'admin';
    const isOnline = d.isOnline ? 1 : 0;
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();
    const updatedAt = d.updatedAt?.toDate ? d.updatedAt.toDate() : new Date();

    sqlStatements.push(`INSERT IGNORE INTO \`events\` (\`id\`, \`title\`, \`description\`, \`location\`, \`location_country\`, \`event_type\`, \`cover_image_url\`, \`link_url\`, \`author_uid\`, \`author_username\`, \`is_online\`, \`created_at\`, \`updated_at\`) VALUES (${escapeSql(id)}, ${escapeSql(title)}, ${escapeSql(description)}, ${escapeSql(location)}, ${escapeSql(locationCountry)}, ${escapeSql(eventType)}, ${escapeSql(coverImageUrl)}, ${escapeSql(linkUrl)}, ${escapeSql(authorUid)}, ${escapeSql(authorUsername)}, ${isOnline}, ${escapeSql(createdAt)}, ${escapeSql(updatedAt)});`);
  }

  // 4. Stories
  console.log('Reading stories...');
  const storyDocs = await db.collection('stories').get();
  console.log(`Found ${storyDocs.size} stories`);
  for (const doc of storyDocs.docs) {
    const d = doc.data();
    const authorUid = d.authorUid || d.uid;
    if (!authorUid) continue;

    const id = doc.id;
    const authorUsername = d.authorUsername || 'unknown';
    const authorAvatar = d.authorAvatar || null;
    const imageUrl = d.imageUrl || '';
    const videoUrl = d.videoUrl || null;
    const textContent = d.textContent || null;
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();
    const expiresAt = d.expiresAt?.toDate ? d.expiresAt.toDate() : new Date(createdAt.getTime() + 24 * 60 * 60 * 1000);

    sqlStatements.push(`INSERT IGNORE INTO \`stories\` (\`id\`, \`author_uid\`, \`author_username\`, \`author_avatar\`, \`image_url\`, \`video_url\`, \`text_content\`, \`created_at\`, \`expires_at\`) VALUES (${escapeSql(id)}, ${escapeSql(authorUid)}, ${escapeSql(authorUsername)}, ${escapeSql(authorAvatar)}, ${escapeSql(imageUrl)}, ${escapeSql(videoUrl)}, ${escapeSql(textContent)}, ${escapeSql(createdAt)}, ${escapeSql(expiresAt)});`);
  }

  // 5. Chats & Messages
  console.log('Reading chats...');
  const chatDocs = await db.collection('chats').get();
  console.log(`Found ${chatDocs.size} chats`);
  for (const doc of chatDocs.docs) {
    const d = doc.data();
    const id = doc.id;
    const kind = d.kind || 'direct';
    const groupName = d.groupName || '';
    const lastMessage = d.lastMessage || '';
    const lastMessageSenderUid = d.lastMessageSenderUid || '';
    const lastTime = d.lastTime?.toDate ? d.lastTime.toDate() : new Date();
    const participants = JSON.stringify(Array.isArray(d.participants) ? d.participants : []);
    const acceptedBy = JSON.stringify(Array.isArray(d.acceptedBy) ? d.acceptedBy : []);
    const unreadCounts = JSON.stringify(d.unreadCounts || {});
    const userData = JSON.stringify(d.userData || {});
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();
    const updatedAt = d.updatedAt?.toDate ? d.updatedAt.toDate() : new Date();

    sqlStatements.push(`INSERT IGNORE INTO \`chats\` (\`id\`, \`kind\`, \`group_name\`, \`last_message\`, \`last_message_sender_uid\`, \`last_time\`, \`participants\`, \`accepted_by\`, \`unread_counts\`, \`user_data\`, \`created_at\`, \`updated_at\`) VALUES (${escapeSql(id)}, ${escapeSql(kind)}, ${escapeSql(groupName)}, ${escapeSql(lastMessage)}, ${escapeSql(lastMessageSenderUid)}, ${escapeSql(lastTime)}, ${escapeSql(participants)}, ${escapeSql(acceptedBy)}, ${escapeSql(unreadCounts)}, ${escapeSql(userData)}, ${escapeSql(createdAt)}, ${escapeSql(updatedAt)});`);

    // Subcollection messages
    const msgDocs = await db.collection('chats').doc(id).collection('messages').get();
    for (const mDoc of msgDocs.docs) {
      const md = mDoc.data();
      if (!md.senderUid) continue;

      const mId = mDoc.id;
      const mText = md.text || '';
      const mImage = md.imageUrl || null;
      const mVideo = md.videoUrl || null;
      const mVoice = md.voiceUrl || null;
      const mCreatedAt = md.createdAt?.toDate ? md.createdAt.toDate() : new Date();

      sqlStatements.push(`INSERT IGNORE INTO \`messages\` (\`id\`, \`chat_id\`, \`sender_uid\`, \`text\`, \`image_url\`, \`video_url\`, \`voice_url\`, \`created_at\`) VALUES (${escapeSql(mId)}, ${escapeSql(id)}, ${escapeSql(md.senderUid)}, ${escapeSql(mText)}, ${escapeSql(mImage)}, ${escapeSql(mVideo)}, ${escapeSql(mVoice)}, ${escapeSql(mCreatedAt)});`);
    }
  }

  sqlStatements.push('SET FOREIGN_KEY_CHECKS = 1;');

  const outPath = path.join(__dirname, 'firebase_export.sql');
  fs.writeFileSync(outPath, sqlStatements.join('\n'), 'utf8');
  console.log(`\n🎉 Generated SQL export with ${sqlStatements.length} statements at:\n${outPath}`);
  process.exit(0);
}

exportFirestoreToSql().catch(err => {
  console.error('Fatal export error:', err);
  process.exit(1);
});
