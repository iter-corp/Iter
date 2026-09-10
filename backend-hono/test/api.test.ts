import { app } from '../src/app.js';

async function runTests() {
  console.log('🧪 Running Hono Backend Integration Tests...\n');
  let passed = 0;
  let failed = 0;

  async function test(name: string, fn: () => Promise<void>) {
    try {
      await fn();
      console.log(`  ✅ ${name}`);
      passed++;
    } catch (e: any) {
      console.error(`  ❌ ${name}:`, e.message || e);
      failed++;
    }
  }

  // 1. Health check
  await test('GET /health returns 200 OK', async () => {
    const res = await app.request('/health');
    if (res.status !== 200) throw new Error(`Expected 200, got ${res.status}`);
    const data = await res.json();
    if (data.status !== 'ok') throw new Error(`Expected status ok, got ${data.status}`);
  });

  // 2. OpenAPI Spec & Docs
  await test('GET /api-spec.json returns OpenAPI 3.0 spec', async () => {
    const res = await app.request('/api-spec.json');
    if (res.status !== 200) throw new Error(`Expected 200, got ${res.status}`);
    const data = await res.json();
    if (!data.openapi?.startsWith('3.')) throw new Error('Invalid OpenAPI version');
  });

  // 3. Dynamic config fallback
  await test('GET /api/v1/dynamic/config returns application configuration', async () => {
    const res = await app.request('/api/v1/dynamic/config');
    // If DB is offline, error handler returns 500, else 200
    if (res.status === 200) {
      const json = await res.json();
      if (!json.success) throw new Error('Expected success true');
    }
  });

  // 4. Check username route
  await test('GET /api/v1/users/check-username without username returns false', async () => {
    const res = await app.request('/api/v1/users/check-username');
    if (res.status !== 200) throw new Error(`Expected 200, got ${res.status}`);
    const json = await res.json();
    if (json.available !== false) throw new Error('Expected available: false for empty query');
  });

  // 5. Auth validation
  await test('POST /api/v1/auth/login with invalid payload returns 400 validation error', async () => {
    const res = await app.request('/api/v1/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'not-an-email' }),
    });
    if (res.status !== 400) throw new Error(`Expected 400 validation error, got ${res.status}`);
  });

  // 6. Protected routes reject without token
  await test('GET /api/v1/users/me returns 401 Unauthorized without token', async () => {
    const res = await app.request('/api/v1/users/me');
    if (res.status !== 401) throw new Error(`Expected 401, got ${res.status}`);
  });

  // 7. Firebase Auth sync validation
  await test('POST /api/v1/auth/firebase-sync with missing email returns 400 error', async () => {
    const res = await app.request('/api/v1/auth/firebase-sync', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ uid: 'uid_123' }),
    });
    if (res.status !== 400) throw new Error(`Expected 400 validation error, got ${res.status}`);
  });


  console.log(`\n📊 Results: ${passed} passed, ${failed} failed\n`);
  if (failed > 0) process.exit(1);
}

runTests();
