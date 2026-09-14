const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

async function exportAllFirestoreData(targetBaseUrl = 'https://iterglobal.icu', outFileName = 'full_export.sql') {
  console.log(`\n🚀 Exporting all Firestore data to SQL for target: ${targetBaseUrl}...`);

  const saPath = path.join(__dirname, 'serviceAccountKey.json');
  if (!fs.existsSync(saPath)) {
    console.error('❌ serviceAccountKey.json not found in backend-hono!');
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
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

  function normalizeUrl(url) {
    if (!url || typeof url !== 'string') return url;
    // Replace Supabase storage URLs with new server URL
    const supabasePattern = /https:\/\/htiwlasyspclmsyslaco\.supabase\.co\/storage\/v1\/object\/public\//g;
    let u = url.replace(supabasePattern, `${targetBaseUrl}/uploads/`);
    // Replace old local URLs (e.g. http://192.168.x.x:3000/uploads/ or http://localhost:3000/uploads/)
    u = u.replace(/http:\/\/(localhost|127\.0\.0\.1|192\.168\.\d+\.\d+)(:\d+)?\/uploads\//g, `${targetBaseUrl}/uploads/`);
    return u;
  }

  function normalizeUrls(urls) {
    if (!Array.isArray(urls)) return [];
    return urls.map(normalizeUrl);
  }

  sqlStatements.push('-- Complete Iter / Coil Firebase to MySQL Data Export');
  sqlStatements.push('SET FOREIGN_KEY_CHECKS = 0;');

  // Maps to accumulate relationships
  const followPairs = new Set(); // set of `${followerUid}_${targetUid}`
  const userFollowersCount = new Map();
  const userFollowingCount = new Map();
  const userPostsCount = new Map();
  const postLikesSet = new Set(); // set of `${postId}_${uid}`
  const postRepostsSet = new Set(); // set of `${postId}_${uid}`
  const postSavesSet = new Set(); // set of `${postId}_${uid}`
  const profileVisitorsList = []; // { ownerUid, visitorUid, visitCount, lastVisitedAt }

  // 1. Fetch all users
  console.log('Fetching users and user subcollections...');
  const userDocs = await db.collection('users').get();
  console.log(`Found ${userDocs.size} users`);

  for (const doc of userDocs.docs) {
    const d = doc.data();
    const uid = doc.id;

    // Subcollection: followers
    try {
      const followersSnap = await doc.ref.collection('followers').get();
      for (const fDoc of followersSnap.docs) {
        const followerUid = fDoc.id;
        if (followerUid && followerUid !== uid) {
          followPairs.add(`${followerUid}_${uid}`);
          userFollowersCount.set(uid, (userFollowersCount.get(uid) || 0) + 1);
          userFollowingCount.set(followerUid, (userFollowingCount.get(followerUid) || 0) + 1);
        }
      }
    } catch (_) {}

    // Subcollection: following
    try {
      const followingSnap = await doc.ref.collection('following').get();
      for (const fDoc of followingSnap.docs) {
        const targetUid = fDoc.id;
        if (targetUid && targetUid !== uid) {
          followPairs.add(`${uid}_${targetUid}`);
          userFollowingCount.set(uid, (userFollowingCount.get(uid) || 0) + 1);
          userFollowersCount.set(targetUid, (userFollowersCount.get(targetUid) || 0) + 1);
        }
      }
    } catch (_) {}

    // Subcollection: saved
    try {
      const savedSnap = await doc.ref.collection('saved').get();
      for (const sDoc of savedSnap.docs) {
        const postId = sDoc.id;
        postSavesSet.add(`${postId}_${uid}`);
      }
    } catch (_) {}

    // Subcollection: reposts
    try {
      const repostsSnap = await doc.ref.collection('reposts').get();
      for (const rDoc of repostsSnap.docs) {
        const postId = rDoc.id;
        postRepostsSet.add(`${postId}_${uid}`);
      }
    } catch (_) {}

    // Subcollection: visitors
    try {
      const visitorsSnap = await doc.ref.collection('visitors').get();
      for (const vDoc of visitorsSnap.docs) {
        const visitorUid = vDoc.id;
        const vd = vDoc.data();
        const visitCount = Number(vd.count) || 1;
        const lastVisitedAt = vd.lastVisitedAt?.toDate ? vd.lastVisitedAt.toDate() : (d.createdAt?.toDate ? d.createdAt.toDate() : new Date());
        profileVisitorsList.push({
          ownerUid: uid,
          visitorUid,
          visitCount,
          lastVisitedAt
        });
      }
    } catch (_) {}
  }

  // 2. Fetch all posts & comments & likes & reposts
  console.log('Fetching posts and post subcollections...');
  const postDocs = await db.collection('posts').get();
  console.log(`Found ${postDocs.size} posts`);

  const commentsList = [];

  for (const doc of postDocs.docs) {
    const d = doc.data();
    const postId = doc.id;
    const authorUid = d.authorUid || d.uid;
    if (authorUid) {
      userPostsCount.set(authorUid, (userPostsCount.get(authorUid) || 0) + 1);
    }

    // Likes subcollection
    try {
      const likesSnap = await doc.ref.collection('likes').get();
      for (const lDoc of likesSnap.docs) {
        postLikesSet.add(`${postId}_${lDoc.id}`);
      }
    } catch (_) {}

    // Reposts subcollection
    try {
      const repostsSnap = await doc.ref.collection('reposts').get();
      for (const rDoc of repostsSnap.docs) {
        postRepostsSet.add(`${postId}_${rDoc.id}`);
      }
    } catch (_) {}

    // Comments subcollection
    try {
      const commentDocs = await doc.ref.collection('comments').get();
      for (const cDoc of commentDocs.docs) {
        const cd = cDoc.data();
        const cAuthorUid = cd.authorUid || cd.uid;
        if (!cAuthorUid) continue;

        commentsList.push({
          id: cDoc.id,
          postId,
          authorUid: cAuthorUid,
          authorUsername: cd.authorUsername || cd.username || 'user',
          authorAvatar: normalizeUrl(cd.authorAvatar || cd.avatarUrl || null),
          text: cd.text || cd.comment || '',
          parentCommentId: cd.parentCommentId || null,
          replyToUsername: cd.replyToUsername || null,
          helpfulCount: Number(cd.helpfulCount) || 0,
          unhelpfulCount: Number(cd.unhelpfulCount) || 0,
          likesCount: Number(cd.likesCount) || 0,
          createdAt: cd.createdAt?.toDate ? cd.createdAt.toDate() : new Date(),
          updatedAt: cd.updatedAt?.toDate ? cd.updatedAt.toDate() : new Date(),
        });
      }
    } catch (_) {}
  }

  // Write Users table
  console.log('Generating Users SQL...');
  for (const doc of userDocs.docs) {
    const d = doc.data();
    const id = doc.id;
    const email = (d.email || `${id}@iter.local`).toLowerCase();
    const emailVerified = d.emailVerified ? 1 : 0;
    const username = d.username || null;
    const usernameLower = d.usernameLower || (username ? username.toLowerCase() : null);
    const handle = d.handle || null;
    const bio = d.bio || '';
    const avatarUrl = normalizeUrl(d.avatarUrl || null);
    const coverUrl = normalizeUrl(d.coverUrl || null);
    const gender = d.gender || null;
    const role = d.role || 'user';
    const isPrivate = d.isPrivate ? 1 : 0;
    const appIntroSeen = d.appIntroSeen !== false ? 1 : 0;
    
    // Accurate counts from relationships
    const followersCount = userFollowersCount.get(id) ?? (Number(d.followersCount) || 0);
    const followingCount = userFollowingCount.get(id) ?? (Number(d.followingCount) || 0);
    const postsCount = userPostsCount.get(id) ?? (Number(d.postsCount) || 0);
    
    const profession = d.profession || null;
    const field = d.field || null;
    const academicLevel = d.academicLevel || null;
    const goals = JSON.stringify(Array.isArray(d.goals) ? d.goals : []);
    const blockedUsers = JSON.stringify(Array.isArray(d.blockedUsers) ? d.blockedUsers : []);
    const metadata = JSON.stringify(d.metadata || {});
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();
    const updatedAt = d.updatedAt?.toDate ? d.updatedAt.toDate() : new Date();

    sqlStatements.push(`INSERT INTO \`users\` (\`id\`, \`email\`, \`email_verified\`, \`username\`, \`username_lower\`, \`handle\`, \`bio\`, \`avatar_url\`, \`cover_url\`, \`gender\`, \`role\`, \`is_private\`, \`app_intro_seen\`, \`followers_count\`, \`following_count\`, \`posts_count\`, \`profession\`, \`field\`, \`academic_level\`, \`goals\`, \`blocked_users\`, \`metadata\`, \`created_at\`, \`updated_at\`)
VALUES (${escapeSql(id)}, ${escapeSql(email)}, ${emailVerified}, ${escapeSql(username)}, ${escapeSql(usernameLower)}, ${escapeSql(handle)}, ${escapeSql(bio)}, ${escapeSql(avatarUrl)}, ${escapeSql(coverUrl)}, ${escapeSql(gender)}, ${escapeSql(role)}, ${isPrivate}, ${appIntroSeen}, ${followersCount}, ${followingCount}, ${postsCount}, ${escapeSql(profession)}, ${escapeSql(field)}, ${escapeSql(academicLevel)}, ${escapeSql(goals)}, ${escapeSql(blockedUsers)}, ${escapeSql(metadata)}, ${escapeSql(createdAt)}, ${escapeSql(updatedAt)})
ON DUPLICATE KEY UPDATE \`followers_count\` = ${followersCount}, \`following_count\` = ${followingCount}, \`posts_count\` = ${postsCount}, \`avatar_url\` = COALESCE(${escapeSql(avatarUrl)}, \`avatar_url\`), \`cover_url\` = COALESCE(${escapeSql(coverUrl)}, \`cover_url\`);`);
  }

  // Write Follows table
  console.log(`Generating Follows SQL (${followPairs.size} relationships)...`);
  for (const pair of followPairs) {
    const [followerUid, targetUid] = pair.split('_');
    if (!followerUid || !targetUid) continue;
    sqlStatements.push(`INSERT IGNORE INTO \`follows\` (\`id\`, \`follower_uid\`, \`target_uid\`, \`status\`, \`created_at\`) VALUES (${escapeSql(pair)}, ${escapeSql(followerUid)}, ${escapeSql(targetUid)}, 'active', NOW());`);
  }

  // Write Posts table
  console.log('Generating Posts SQL...');
  for (const doc of postDocs.docs) {
    const d = doc.data();
    const id = doc.id;
    const authorUid = d.authorUid || d.uid;
    if (!authorUid) continue;

    const authorUsername = d.authorUsername || d.username || 'unknown';
    const authorAvatar = normalizeUrl(d.authorAvatar || d.avatarUrl || null);
    const caption = d.caption || d.text || '';
    
    let rawImages = Array.isArray(d.imageUrls) ? d.imageUrls : (d.imageUrl ? [d.imageUrl] : []);
    let rawVideos = Array.isArray(d.videoUrls) ? d.videoUrls : (d.videoUrl ? [d.videoUrl] : []);
    const imageUrls = JSON.stringify(normalizeUrls(rawImages));
    const videoUrls = JSON.stringify(normalizeUrls(rawVideos));
    
    // Count likes from postLikesSet for this post
    let actualLikes = 0;
    for (const likePair of postLikesSet) {
      if (likePair.startsWith(`${id}_`)) actualLikes++;
    }
    const likesCount = actualLikes > 0 ? actualLikes : (Number(d.likesCount) || 0);

    // Count comments
    let actualComments = 0;
    for (const c of commentsList) {
      if (c.postId === id) actualComments++;
    }
    const commentsCount = actualComments > 0 ? actualComments : Math.max(Number(d.commentsCount) || 0, 0);

    const isPrivate = d.isPrivate ? 1 : 0;
    const postType = d.postType || (d.isQa ? 'qa' : 'regular');
    const discussKind = d.discussKind || 'question';
    const sourcePostId = d.sourcePostId || null;
    const postPlaceName = d.postPlaceName || null;
    const postPlaceCity = d.postPlaceCity || null;
    const postLat = typeof d.postLat === 'number' ? d.postLat : null;
    const postLng = typeof d.postLng === 'number' ? d.postLng : null;
    const postLocationExact = d.postLocationExact ? 1 : 0;
    const metadata = JSON.stringify(d.metadata || {});
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();
    const updatedAt = d.updatedAt?.toDate ? d.updatedAt.toDate() : new Date();

    sqlStatements.push(`INSERT INTO \`posts\` (\`id\`, \`author_uid\`, \`author_username\`, \`author_avatar\`, \`caption\`, \`image_urls\`, \`video_urls\`, \`likes_count\`, \`comments_count\`, \`is_private\`, \`post_type\`, \`discuss_kind\`, \`source_post_id\`, \`post_place_name\`, \`post_place_city\`, \`post_lat\`, \`post_lng\`, \`post_location_exact\`, \`metadata\`, \`created_at\`, \`updated_at\`)
VALUES (${escapeSql(id)}, ${escapeSql(authorUid)}, ${escapeSql(authorUsername)}, ${escapeSql(authorAvatar)}, ${escapeSql(caption)}, ${escapeSql(imageUrls)}, ${escapeSql(videoUrls)}, ${likesCount}, ${commentsCount}, ${isPrivate}, ${escapeSql(postType)}, ${escapeSql(discussKind)}, ${escapeSql(sourcePostId)}, ${escapeSql(postPlaceName)}, ${escapeSql(postPlaceCity)}, ${escapeSql(postLat)}, ${escapeSql(postLng)}, ${postLocationExact}, ${escapeSql(metadata)}, ${escapeSql(createdAt)}, ${escapeSql(updatedAt)})
ON DUPLICATE KEY UPDATE \`likes_count\` = ${likesCount}, \`comments_count\` = ${commentsCount}, \`image_urls\` = ${escapeSql(imageUrls)}, \`video_urls\` = ${escapeSql(videoUrls)}, \`author_avatar\` = COALESCE(${escapeSql(authorAvatar)}, \`author_avatar\`);`);
  }

  // Write Post Likes
  console.log(`Generating Post Likes SQL (${postLikesSet.size} likes)...`);
  for (const pair of postLikesSet) {
    const [postId, uid] = pair.split('_');
    if (!postId || !uid) continue;
    sqlStatements.push(`INSERT IGNORE INTO \`post_likes\` (\`id\`, \`post_id\`, \`uid\`, \`created_at\`) VALUES (${escapeSql(pair)}, ${escapeSql(postId)}, ${escapeSql(uid)}, NOW());`);
  }

  // Write Post Reposts
  console.log(`Generating Post Reposts SQL (${postRepostsSet.size} reposts)...`);
  for (const pair of postRepostsSet) {
    const [postId, uid] = pair.split('_');
    if (!postId || !uid) continue;
    sqlStatements.push(`INSERT IGNORE INTO \`post_reposts\` (\`id\`, \`post_id\`, \`uid\`, \`created_at\`) VALUES (${escapeSql(pair)}, ${escapeSql(postId)}, ${escapeSql(uid)}, NOW());`);
  }

  // Write Post Saves
  console.log(`Generating Post Saves SQL (${postSavesSet.size} saves)...`);
  for (const pair of postSavesSet) {
    const [postId, uid] = pair.split('_');
    if (!postId || !uid) continue;
    sqlStatements.push(`INSERT IGNORE INTO \`post_saves\` (\`id\`, \`post_id\`, \`uid\`, \`created_at\`) VALUES (${escapeSql(pair)}, ${escapeSql(postId)}, ${escapeSql(uid)}, NOW());`);
  }

  // Write Profile Visitors
  console.log(`Generating Profile Visitors SQL (${profileVisitorsList.length} visitors)...`);
  for (const v of profileVisitorsList) {
    sqlStatements.push(`INSERT INTO \`profile_visitors\` (\`owner_uid\`, \`visitor_uid\`, \`visit_count\`, \`last_visited_at\`)
VALUES (${escapeSql(v.ownerUid)}, ${escapeSql(v.visitorUid)}, ${v.visitCount}, ${escapeSql(v.lastVisitedAt)})
ON DUPLICATE KEY UPDATE \`visit_count\` = VALUES(\`visit_count\`), \`last_visited_at\` = VALUES(\`last_visited_at\`);`);
  }

  // Write Comments
  console.log(`Generating Comments SQL (${commentsList.length} comments)...`);
  for (const c of commentsList) {
    sqlStatements.push(`INSERT INTO \`comments\` (\`id\`, \`post_id\`, \`author_uid\`, \`author_username\`, \`author_avatar\`, \`text\`, \`parent_comment_id\`, \`reply_to_username\`, \`helpful_count\`, \`unhelpful_count\`, \`likes_count\`, \`created_at\`, \`updated_at\`)
VALUES (${escapeSql(c.id)}, ${escapeSql(c.postId)}, ${escapeSql(c.authorUid)}, ${escapeSql(c.authorUsername)}, ${escapeSql(c.authorAvatar)}, ${escapeSql(c.text)}, ${escapeSql(c.parentCommentId)}, ${escapeSql(c.replyToUsername)}, ${c.helpfulCount}, ${c.unhelpfulCount}, ${c.likesCount}, ${escapeSql(c.createdAt)}, ${escapeSql(c.updatedAt)})
ON DUPLICATE KEY UPDATE \`text\` = VALUES(\`text\`), \`likes_count\` = VALUES(\`likes_count\`);`);
  }

  // 3. Events & Event Registrations
  console.log('Fetching events...');
  const eventDocs = await db.collection('events').get();
  console.log(`Found ${eventDocs.size} events`);
  for (const doc of eventDocs.docs) {
    const d = doc.data();
    const id = doc.id;
    const authorUid = d.authorUid || d.createdByUid || d.uid;
    if (!authorUid) continue;

    const title = d.title || 'Untitled Event';
    const description = d.description || '';
    const location = d.location || '';
    const locationCountry = (d.locationCountry || 'other').toLowerCase();
    const eventType = d.eventType || 'other';
    const coverImageUrl = normalizeUrl(d.coverImageUrl || null);
    const linkUrl = d.linkUrl || null;
    const authorUsername = d.authorUsername || 'admin';
    const authorAvatar = normalizeUrl(d.authorAvatar || null);
    const isOnline = d.isOnline ? 1 : 0;
    const capacity = typeof d.capacity === 'number' ? d.capacity : null;
    const startDate = d.startDate?.toDate ? d.startDate.toDate() : null;
    const endDate = d.endDate?.toDate ? d.endDate.toDate() : null;
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();
    const updatedAt = d.updatedAt?.toDate ? d.updatedAt.toDate() : new Date();

    sqlStatements.push(`INSERT INTO \`events\` (\`id\`, \`title\`, \`description\`, \`location\`, \`location_country\`, \`event_type\`, \`cover_image_url\`, \`link_url\`, \`capacity\`, \`start_date\`, \`end_date\`, \`author_uid\`, \`author_username\`, \`author_avatar\`, \`is_online\`, \`created_at\`, \`updated_at\`)
VALUES (${escapeSql(id)}, ${escapeSql(title)}, ${escapeSql(description)}, ${escapeSql(location)}, ${escapeSql(locationCountry)}, ${escapeSql(eventType)}, ${escapeSql(coverImageUrl)}, ${escapeSql(linkUrl)}, ${escapeSql(capacity)}, ${escapeSql(startDate)}, ${escapeSql(endDate)}, ${escapeSql(authorUid)}, ${escapeSql(authorUsername)}, ${escapeSql(authorAvatar)}, ${isOnline}, ${escapeSql(createdAt)}, ${escapeSql(updatedAt)})
ON DUPLICATE KEY UPDATE \`cover_image_url\` = COALESCE(${escapeSql(coverImageUrl)}, \`cover_image_url\`);`);
  }

  // Event Registrations
  console.log('Fetching event registrations...');
  const regDocs = await db.collection('eventRegistrations').get();
  console.log(`Found ${regDocs.size} event registrations`);
  for (const doc of regDocs.docs) {
    const d = doc.data();
    const id = doc.id;
    if (!d.eventId || !d.userUid) continue;

    const eventTitle = d.eventTitle || '';
    const name = d.name || '';
    const email = d.email || '';
    const phone = d.phone || '';
    const countryCode = d.countryCode || '+1';
    const status = d.status || 'pending';
    const reviewedAt = d.reviewedAt?.toDate ? d.reviewedAt.toDate() : null;
    const reviewedBy = d.reviewedBy || null;
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();

    sqlStatements.push(`INSERT IGNORE INTO \`event_registrations\` (\`id\`, \`event_id\`, \`event_title\`, \`user_uid\`, \`name\`, \`email\`, \`phone\`, \`country_code\`, \`status\`, \`reviewed_at\`, \`reviewed_by\`, \`created_at\`)
VALUES (${escapeSql(id)}, ${escapeSql(d.eventId)}, ${escapeSql(eventTitle)}, ${escapeSql(d.userUid)}, ${escapeSql(name)}, ${escapeSql(email)}, ${escapeSql(phone)}, ${escapeSql(countryCode)}, ${escapeSql(status)}, ${escapeSql(reviewedAt)}, ${escapeSql(reviewedBy)}, ${escapeSql(createdAt)});`);
  }

  // 4. Stories
  console.log('Fetching stories...');
  const storyDocs = await db.collection('stories').get();
  console.log(`Found ${storyDocs.size} stories`);
  for (const doc of storyDocs.docs) {
    const d = doc.data();
    const id = doc.id;
    const authorUid = d.authorUid || d.uid;
    if (!authorUid) continue;

    const authorUsername = d.authorUsername || 'unknown';
    const authorAvatar = normalizeUrl(d.authorAvatar || null);
    const imageUrl = normalizeUrl(d.imageUrl || '');
    const videoUrl = normalizeUrl(d.videoUrl || null);
    const textContent = d.textContent || null;
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();
    const expiresAt = d.expiresAt?.toDate ? d.expiresAt.toDate() : new Date(createdAt.getTime() + 24 * 60 * 60 * 1000);

    sqlStatements.push(`INSERT INTO \`stories\` (\`id\`, \`author_uid\`, \`author_username\`, \`author_avatar\`, \`image_url\`, \`video_url\`, \`text_content\`, \`created_at\`, \`expires_at\`)
VALUES (${escapeSql(id)}, ${escapeSql(authorUid)}, ${escapeSql(authorUsername)}, ${escapeSql(authorAvatar)}, ${escapeSql(imageUrl)}, ${escapeSql(videoUrl)}, ${escapeSql(textContent)}, ${escapeSql(createdAt)}, ${escapeSql(expiresAt)})
ON DUPLICATE KEY UPDATE \`image_url\` = ${escapeSql(imageUrl)}, \`video_url\` = ${escapeSql(videoUrl)};`);
  }

  // 5. Chats & Messages
  console.log('Fetching chats & messages...');
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

    sqlStatements.push(`INSERT INTO \`chats\` (\`id\`, \`kind\`, \`group_name\`, \`last_message\`, \`last_message_sender_uid\`, \`last_time\`, \`participants\`, \`accepted_by\`, \`unread_counts\`, \`user_data\`, \`created_at\`, \`updated_at\`)
VALUES (${escapeSql(id)}, ${escapeSql(kind)}, ${escapeSql(groupName)}, ${escapeSql(lastMessage)}, ${escapeSql(lastMessageSenderUid)}, ${escapeSql(lastTime)}, ${escapeSql(participants)}, ${escapeSql(acceptedBy)}, ${escapeSql(unreadCounts)}, ${escapeSql(userData)}, ${escapeSql(createdAt)}, ${escapeSql(updatedAt)})
ON DUPLICATE KEY UPDATE \`last_message\` = VALUES(\`last_message\`), \`last_time\` = VALUES(\`last_time\`);`);

    // Messages
    try {
      const msgDocs = await doc.ref.collection('messages').get();
      for (const mDoc of msgDocs.docs) {
        const md = mDoc.data();
        if (!md.senderUid) continue;

        const mId = mDoc.id;
        const mText = md.text || '';
        const mImage = normalizeUrl(md.imageUrl || null);
        const mVideo = normalizeUrl(md.videoUrl || null);
        const mVoice = normalizeUrl(md.voiceUrl || null);
        const mCreatedAt = md.createdAt?.toDate ? md.createdAt.toDate() : new Date();

        sqlStatements.push(`INSERT IGNORE INTO \`messages\` (\`id\`, \`chat_id\`, \`sender_uid\`, \`text\`, \`image_url\`, \`video_url\`, \`voice_url\`, \`created_at\`)
VALUES (${escapeSql(mId)}, ${escapeSql(id)}, ${escapeSql(md.senderUid)}, ${escapeSql(mText)}, ${escapeSql(mImage)}, ${escapeSql(mVideo)}, ${escapeSql(mVoice)}, ${escapeSql(mCreatedAt)});`);
      }
    } catch (_) {}
  }

  // 6. Blacklist
  console.log('Fetching blacklist...');
  const blacklistDocs = await db.collection('blacklist').get();
  for (const doc of blacklistDocs.docs) {
    const d = doc.data();
    const emailOrDomain = d.email || doc.id;
    const reason = d.selfDeleted ? 'Self deleted account' : (d.reason || null);
    const createdAt = d.deletedAt?.toDate ? d.deletedAt.toDate() : new Date();

    sqlStatements.push(`INSERT IGNORE INTO \`blacklist\` (\`email_or_domain\`, \`reason\`, \`created_at\`)
VALUES (${escapeSql(emailOrDomain)}, ${escapeSql(reason)}, ${escapeSql(createdAt)});`);
  }

  // 7. User Reports
  console.log('Fetching user reports...');
  const userReportDocs = await db.collection('userReports').get();
  for (const doc of userReportDocs.docs) {
    const d = doc.data();
    const id = doc.id;
    if (!d.targetUid || !d.reporterUid) continue;
    const targetUsername = d.targetUsername || 'unknown';
    const reporterUsername = d.reporterUsername || 'unknown';
    const reason = d.reason || 'Report';
    const details = d.details || null;
    const resolved = d.resolved ? 1 : 0;
    const resolvedAt = d.resolvedAt?.toDate ? d.resolvedAt.toDate() : null;
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();

    sqlStatements.push(`INSERT IGNORE INTO \`user_reports\` (\`id\`, \`target_uid\`, \`target_username\`, \`reporter_uid\`, \`reporter_username\`, \`reason\`, \`details\`, \`resolved\`, \`resolved_at\`, \`created_at\`)
VALUES (${escapeSql(id)}, ${escapeSql(d.targetUid)}, ${escapeSql(targetUsername)}, ${escapeSql(d.reporterUid)}, ${escapeSql(reporterUsername)}, ${escapeSql(reason)}, ${escapeSql(details)}, ${resolved}, ${escapeSql(resolvedAt)}, ${escapeSql(createdAt)});`);
  }

  // 8. Comment Reports
  console.log('Fetching comment reports...');
  const commentReportDocs = await db.collection('commentReports').get();
  for (const doc of commentReportDocs.docs) {
    const d = doc.data();
    const id = doc.id;
    if (!d.commentId || !d.postId || !d.reporterUid) continue;

    const commentAuthorUid = d.commentAuthorUid || 'unknown';
    const commentAuthorUsername = d.commentAuthorUsername || 'unknown';
    const commentText = d.commentText || '';
    const reporterUsername = d.reporterUsername || 'unknown';
    const reason = d.reason || 'Report';
    const resolved = d.resolved ? 1 : 0;
    const resolvedAt = d.resolvedAt?.toDate ? d.resolvedAt.toDate() : null;
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();

    sqlStatements.push(`INSERT IGNORE INTO \`comment_reports\` (\`id\`, \`comment_id\`, \`post_id\`, \`comment_author_uid\`, \`comment_author_username\`, \`comment_text\`, \`reporter_uid\`, \`reporter_username\`, \`reason\`, \`resolved\`, \`resolved_at\`, \`created_at\`)
VALUES (${escapeSql(id)}, ${escapeSql(d.commentId)}, ${escapeSql(d.postId)}, ${escapeSql(commentAuthorUid)}, ${escapeSql(commentAuthorUsername)}, ${escapeSql(commentText)}, ${escapeSql(d.reporterUid)}, ${escapeSql(reporterUsername)}, ${escapeSql(reason)}, ${resolved}, ${escapeSql(resolvedAt)}, ${escapeSql(createdAt)});`);
  }

  // 9. Contact Requests
  console.log('Fetching contact requests...');
  const contactDocs = await db.collection('contactRequests').get();
  for (const doc of contactDocs.docs) {
    const d = doc.data();
    const id = doc.id;
    if (!d.userUid) continue;

    const username = d.userName || 'user';
    const email = d.userEmail || '';
    const type = d.type || 'message';
    const subject = d.subject || '';
    const message = d.lastMessagePreview || '';
    const status = d.status || 'open';
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();
    const updatedAt = d.lastMessageAt?.toDate ? d.lastMessageAt.toDate() : createdAt;

    sqlStatements.push(`INSERT IGNORE INTO \`contact_requests\` (\`id\`, \`user_uid\`, \`username\`, \`email\`, \`type\`, \`subject\`, \`message\`, \`status\`, \`created_at\`, \`updated_at\`)
VALUES (${escapeSql(id)}, ${escapeSql(d.userUid)}, ${escapeSql(username)}, ${escapeSql(email)}, ${escapeSql(type)}, ${escapeSql(subject)}, ${escapeSql(message)}, ${escapeSql(status)}, ${escapeSql(createdAt)}, ${escapeSql(updatedAt)});`);
  }

  // 10. API Keys
  console.log('Fetching API keys...');
  const keyDocs = await db.collection('apiKeys').get();
  for (const doc of keyDocs.docs) {
    const d = doc.data();
    const id = doc.id;
    const provider = d.provider || 'gemini';
    const key = d.key || '';
    const active = d.active !== false ? 1 : 0;
    const priority = Number(d.priority) || 999;
    const statusMessage = d.statusMessage || null;
    const lastChecked = d.lastChecked?.toDate ? d.lastChecked.toDate() : null;
    const createdAt = d.createdAt?.toDate ? d.createdAt.toDate() : new Date();

    sqlStatements.push(`INSERT INTO \`api_keys\` (\`id\`, \`provider\`, \`key\`, \`active\`, \`priority\`, \`status_message\`, \`last_checked\`, \`created_at\`)
VALUES (${escapeSql(id)}, ${escapeSql(provider)}, ${escapeSql(key)}, ${active}, ${priority}, ${escapeSql(statusMessage)}, ${escapeSql(lastChecked)}, ${escapeSql(createdAt)})
ON DUPLICATE KEY UPDATE \`key\` = VALUES(\`key\`), \`active\` = VALUES(\`active\`), \`priority\` = VALUES(\`priority\`);`);
  }

  // Final count synchronization triggers to guarantee perfect counts:
  sqlStatements.push(`
-- Synchronize exact counts in users and posts
UPDATE \`users\` u SET
  \`followers_count\` = (SELECT COUNT(*) FROM \`follows\` f WHERE f.\`target_uid\` = u.\`id\` AND f.\`status\` = 'active'),
  \`following_count\` = (SELECT COUNT(*) FROM \`follows\` f WHERE f.\`follower_uid\` = u.\`id\` AND f.\`status\` = 'active'),
  \`posts_count\` = (SELECT COUNT(*) FROM \`posts\` p WHERE p.\`author_uid\` = u.\`id\`);

UPDATE \`posts\` p SET
  \`likes_count\` = (SELECT COUNT(*) FROM \`post_likes\` pl WHERE pl.\`post_id\` = p.\`id\`),
  \`comments_count\` = (SELECT COUNT(*) FROM \`comments\` c WHERE c.\`post_id\` = p.\`id\`);
`);

  sqlStatements.push('SET FOREIGN_KEY_CHECKS = 1;');

  const outPath = path.join(__dirname, outFileName);
  fs.writeFileSync(outPath, sqlStatements.join('\n'), 'utf8');
  console.log(`\n🎉 Generated SQL export with ${sqlStatements.length} statements at:\n${outPath}`);
  return outPath;
}

async function run() {
  await exportAllFirestoreData('https://iterglobal.icu', 'full_export_prod.sql');
  await exportAllFirestoreData('https://dev.iterglobal.icu', 'full_export_dev.sql');
  console.log('✅ Both production and dev SQL exports generated successfully.');
  process.exit(0);
}

run().catch(err => {
  console.error('Fatal export error:', err);
  process.exit(1);
});
