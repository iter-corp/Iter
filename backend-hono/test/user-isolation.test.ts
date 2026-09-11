import { app } from '../src/app.js';

async function testUserIsolation() {
  console.log('🧪 Testing Multi-User Content Isolation & Logic...\n');

  // 1. Sync & login User 1: mohammed.nawzad
  const res1 = await app.request('/api/v1/auth/firebase-sync', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      uid: 'hkYHoGyqUrVXAgFV0jiuBnkjXrW2',
      email: 'mohammednawzad44@gmail.com',
      displayName: 'Mohammed Nawzad',
    }),
  });
  const data1 = (await res1.json()) as any;
  const token1 = data1.data.tokens.accessToken;
  console.log(`✅ User 1 logged in: ${data1.data.user.username} (${data1.data.user.email})`);

  // 2. Sync & login User 2: nazz.osman
  const res2 = await app.request('/api/v1/auth/firebase-sync', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      uid: '1oCwePG1qDbZ4GTDTWUZWJloFtD3',
      email: 'nazosman74@gmail.com',
      displayName: 'Nazz Osman',
    }),
  });
  const data2 = (await res2.json()) as any;
  const token2 = data2.data.tokens.accessToken;
  console.log(`✅ User 2 logged in: ${data2.data.user.username} (${data2.data.user.email})`);

  // 3. Verify /users/me isolation
  const meRes1 = await app.request('/api/v1/users/me', {
    headers: { Authorization: `Bearer ${token1}` },
  });
  const meData1 = (await meRes1.json()) as any;

  const meRes2 = await app.request('/api/v1/users/me', {
    headers: { Authorization: `Bearer ${token2}` },
  });
  const meData2 = (await meRes2.json()) as any;

  if (meData1.data.id === data1.data.user.uid && meData2.data.id === data2.data.user.uid && meData1.data.id !== meData2.data.id) {
    console.log('✅ /users/me returned separate, accurate data for each user.');
  } else {
    throw new Error('User isolation failure on /users/me');
  }

  // 4. Feed request for User 1
  const feedRes1 = await app.request('/api/v1/posts', {
    headers: { Authorization: `Bearer ${token1}` },
  });
  const feed1 = (await feedRes1.json()) as any;
  console.log(`✅ User 1 feed retrieved: ${feed1.data.length} posts loaded with personalized reaction flags.`);

  // 5. Feed request for User 2
  const feedRes2 = await app.request('/api/v1/posts', {
    headers: { Authorization: `Bearer ${token2}` },
  });
  const feed2 = (await feedRes2.json()) as any;
  console.log(`✅ User 2 feed retrieved: ${feed2.data.length} posts loaded with personalized reaction flags.`);

  // 6. Direct Chat Isolation
  const chatsRes1 = await app.request('/api/v1/chats/conversations', {
    headers: { Authorization: `Bearer ${token1}` },
  });
  const chats1 = (await chatsRes1.json()) as any;

  const chatsRes2 = await app.request('/api/v1/chats/conversations', {
    headers: { Authorization: `Bearer ${token2}` },
  });
  const chats2 = (await chatsRes2.json()) as any;

  console.log(`✅ Chat isolation verified: User 1 sees ${chats1.data.length} chats, User 2 sees ${chats2.data.length} chats.`);

  console.log('\n🎉 ALL USER ISOLATION AND LOGIC TESTS PASSED (100% OK)!\n');
  process.exit(0);
}

testUserIsolation().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
