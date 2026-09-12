/**
 * Script to synchronize local uploads to production Hostinger server
 * and migrate legacy Supabase URLs in MariaDB.
 */
const fs = require('fs');
const path = require('path');

const REMOTE_BASE = process.env.REMOTE_URL || 'https://iterglobal.icu';
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'admin@iter.app';
const ADMIN_PASS = process.env.ADMIN_PASS || 'Admin@123456';
const LOCAL_UPLOADS_DIR = path.resolve(__dirname, 'uploads');

async function main() {
  console.log('🚀 Starting Media Synchronization to', REMOTE_BASE);

  // 1. Authenticate as Admin
  console.log(`🔑 Logging in as ${ADMIN_EMAIL}...`);
  const loginRes = await fetch(`${REMOTE_BASE}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: ADMIN_EMAIL, password: ADMIN_PASS }),
  });

  const loginData = await loginRes.json();
  if (!loginData.success || !loginData.data?.tokens?.accessToken) {
    console.error('❌ Admin login failed:', loginData);
    process.exit(1);
  }

  const token = loginData.data.tokens.accessToken;
  console.log('   ✅ Admin authenticated successfully.');

  // 2. Trigger Database URL Migration
  console.log('\n🗄️ Running database legacy URL migration on server...');
  try {
    const fixRes = await fetch(`${REMOTE_BASE}/api/v1/admin/media/fix-urls`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    });
    const fixData = await fixRes.json();
    console.log('   ✅ Database migration result:', fixData);
  } catch (err) {
    console.warn('   ⚠️ fix-urls endpoint note:', err.message);
  }

  // 3. Scan Local Files
  console.log(`\n📂 Scanning local files in: ${LOCAL_UPLOADS_DIR}...`);
  const buckets = ['avatars', 'posts'];
  const allFiles = [];

  for (const bucket of buckets) {
    const bucketDir = path.join(LOCAL_UPLOADS_DIR, bucket);
    if (!fs.existsSync(bucketDir)) continue;

    function walk(dir) {
      for (const item of fs.readdirSync(dir)) {
        const full = path.join(dir, item);
        const stat = fs.statSync(full);
        if (stat.isDirectory()) {
          walk(full);
        } else if (stat.isFile()) {
          const rel = path.relative(bucketDir, full).replace(/\\/g, '/');
          allFiles.push({ bucket, relPath: rel, fullPath: full, size: stat.size });
        }
      }
    }
    walk(bucketDir);
  }

  console.log(`   Found ${allFiles.length} local files to check/sync.`);

  let uploadedCount = 0;
  let skippedCount = 0;
  let errorCount = 0;

  for (let i = 0; i < allFiles.length; i++) {
    const file = allFiles[i];
    const publicUrl = `${REMOTE_BASE}/uploads/${file.bucket}/${file.relPath}`;
    const prefix = `[${i + 1}/${allFiles.length}]`;

    try {
      // Check if file already exists remotely
      const headRes = await fetch(publicUrl, { method: 'HEAD' });
      if (headRes.status === 200) {
        console.log(`${prefix} ⏩ Already exists: ${file.bucket}/${file.relPath}`);
        skippedCount++;
        continue;
      }

      // Upload file
      const buffer = fs.readFileSync(file.fullPath);
      const uploadUrl = `${REMOTE_BASE}/api/v1/admin/media/sync-file?bucket=${encodeURIComponent(file.bucket)}&path=${encodeURIComponent(file.relPath)}`;
      const uploadRes = await fetch(uploadUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/octet-stream',
        },
        body: buffer,
      });

      const uploadData = await uploadRes.json();
      if (uploadData.success) {
        console.log(`${prefix} ✅ Uploaded (${(file.size / 1024).toFixed(1)} KB): ${file.bucket}/${file.relPath}`);
        uploadedCount++;
      } else {
        console.error(`${prefix} ❌ Failed: ${file.bucket}/${file.relPath}`, uploadData);
        errorCount++;
      }
    } catch (e) {
      console.error(`${prefix} ❌ Error uploading ${file.relPath}:`, e.message);
      errorCount++;
    }
  }

  console.log('\n📊 ─────────────────────────────────────────────────────────────');
  console.log('   Synchronization Summary:');
  console.log(`   • Uploaded: ${uploadedCount}`);
  console.log(`   • Skipped:  ${skippedCount}`);
  console.log(`   • Errors:   ${errorCount}`);
  console.log('─────────────────────────────────────────────────────────────\n');
}

main().catch(console.error);
