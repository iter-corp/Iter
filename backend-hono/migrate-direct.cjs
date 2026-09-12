const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function migrate() {
  console.log('⏳ Running direct database migrations...');

  let dbHost = process.env.DB_HOST || '127.0.0.1';
  let dbPort = parseInt(process.env.DB_PORT || '3306', 10);
  let dbUser = process.env.DB_USER || 'u814384925_iter_user';
  let dbPassword = process.env.DB_PASSWORD || 'wkjBgrET&3AU8kqE';
  let dbName = process.env.DB_NAME || 'u814384925_iter_db';

  if (process.env.DATABASE_URL) {
    try {
      const parsed = new URL(process.env.DATABASE_URL);
      dbHost = parsed.hostname || dbHost;
      dbPort = parsed.port ? parseInt(parsed.port, 10) : dbPort;
      dbUser = parsed.username ? decodeURIComponent(parsed.username) : dbUser;
      dbPassword = parsed.password ? decodeURIComponent(parsed.password) : dbPassword;
      if (parsed.pathname && parsed.pathname.length > 1) {
        dbName = parsed.pathname.slice(1);
      }
    } catch (e) {
      console.warn('⚠️ Could not parse DATABASE_URL, falling back to DB_* variables:', e.message);
    }
  }

  const connection = await mysql.createConnection({
    host: dbHost,
    port: dbPort,
    user: dbUser,
    password: dbPassword,
    database: dbName,
    multipleStatements: true,
  });

  try {
    const migrationFile = path.join(__dirname, 'src/db/migrations/0000_stiff_caretaker.sql');
    let rawSql = fs.readFileSync(migrationFile, 'utf8');

    // Split statements by Drizzle breakpoint
    const statements = rawSql
      .split(/-->\s*statement-breakpoint/)
      .map(s => s.trim())
      .filter(s => s.length > 0);

    console.log(`Executing ${statements.length} migration statements on MariaDB...`);
    await connection.query('SET FOREIGN_KEY_CHECKS = 0;');

    for (let i = 0; i < statements.length; i++) {
      let stmt = statements[i];
      if (/^CREATE\s+TABLE\s+/i.test(stmt) && !/^CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+/i.test(stmt)) {
        stmt = stmt.replace(/^CREATE\s+TABLE\s+/i, 'CREATE TABLE IF NOT EXISTS ');
      }
      try {
        await connection.query(stmt);
      } catch (err) {
        // Ignore table already exists, duplicate index, or duplicate constraint
        if (err.errno === 1050 || err.code === 'ER_TABLE_EXISTS_ERROR' || err.errno === 1061 || err.errno === 121 || err.errno === 1826) {
          console.log(`ℹ️ Statement #${i + 1} skipped (${err.sqlMessage || err.message})`);
          continue;
        }
        console.error(`❌ Error in statement #${i + 1}: ${err.sqlMessage || err.message}`);
        console.error('SQL snippet:', stmt.slice(0, 200));
        throw err;
      }
    }

    await connection.query('SET FOREIGN_KEY_CHECKS = 1;');
    console.log('✅ All migrations executed successfully!');

    // Create Drizzle migrations table so drizzle-kit knows it has run
    await connection.query(`
      CREATE TABLE IF NOT EXISTS \`__drizzle_migrations\` (
        id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,
        hash text NOT NULL,
        created_at bigint
      );
    `);

    // Automatically migrate any legacy Supabase storage URLs to active domain
    const targetStorageUrl = (process.env.STORAGE_PUBLIC_URL || 'https://iterglobal.icu/uploads').replace(/\/+$/, '');
    const legacyPrefix = 'https://htiwlasyspclmsyslaco.supabase.co/storage/v1/object/public';
    try {
      console.log(`🔄 Checking database for legacy Supabase URLs -> ${targetStorageUrl}...`);
      await connection.query(
        `UPDATE users SET avatar_url = REPLACE(avatar_url, ?, ?), cover_url = REPLACE(cover_url, ?, ?) WHERE avatar_url LIKE ? OR cover_url LIKE ?`,
        [legacyPrefix, targetStorageUrl, legacyPrefix, targetStorageUrl, `%${legacyPrefix}%`, `%${legacyPrefix}%`]
      );
      await connection.query(
        `UPDATE posts SET author_avatar = REPLACE(author_avatar, ?, ?) WHERE author_avatar LIKE ?`,
        [legacyPrefix, targetStorageUrl, `%${legacyPrefix}%`]
      );
      await connection.query(
        `UPDATE comments SET author_avatar = REPLACE(author_avatar, ?, ?) WHERE author_avatar LIKE ?`,
        [legacyPrefix, targetStorageUrl, `%${legacyPrefix}%`]
      );
      await connection.query(
        `UPDATE events SET cover_image_url = REPLACE(cover_image_url, ?, ?) WHERE cover_image_url LIKE ?`,
        [legacyPrefix, targetStorageUrl, `%${legacyPrefix}%`]
      );
      await connection.query(
        `UPDATE stories SET image_url = REPLACE(image_url, ?, ?), video_url = REPLACE(video_url, ?, ?), author_avatar = REPLACE(author_avatar, ?, ?) WHERE image_url LIKE ? OR video_url LIKE ? OR author_avatar LIKE ?`,
        [legacyPrefix, targetStorageUrl, legacyPrefix, targetStorageUrl, legacyPrefix, targetStorageUrl, `%${legacyPrefix}%`, `%${legacyPrefix}%`, `%${legacyPrefix}%`]
      );

      const [postsToFix] = await connection.query(
        `SELECT id, image_urls, video_urls FROM posts WHERE CAST(image_urls AS CHAR) LIKE ? OR CAST(video_urls AS CHAR) LIKE ?`,
        [`%${legacyPrefix}%`, `%${legacyPrefix}%`]
      );
      if (Array.isArray(postsToFix)) {
        for (const row of postsToFix) {
          let imgUrls = [];
          let vidUrls = [];
          if (typeof row.image_urls === 'string') {
            try { imgUrls = JSON.parse(row.image_urls); } catch (_) {}
          } else if (Array.isArray(row.image_urls)) {
            imgUrls = row.image_urls;
          }
          if (typeof row.video_urls === 'string') {
            try { vidUrls = JSON.parse(row.video_urls); } catch (_) {}
          } else if (Array.isArray(row.video_urls)) {
            vidUrls = row.video_urls;
          }

          const newImgs = imgUrls.map((u) => (typeof u === 'string' ? u.replace(legacyPrefix, targetStorageUrl) : u));
          const newVids = vidUrls.map((u) => (typeof u === 'string' ? u.replace(legacyPrefix, targetStorageUrl) : u));

          await connection.query(
            `UPDATE posts SET image_urls = ?, video_urls = ? WHERE id = ?`,
            [JSON.stringify(newImgs), JSON.stringify(newVids), row.id]
          );
        }
        if (postsToFix.length > 0) {
          console.log(`   ✅ Converted media URLs for ${postsToFix.length} posts.`);
        }
      }
    } catch (urlErr) {
      console.warn('⚠️ Legacy URL conversion note:', urlErr.message);
    }
  } catch (error) {
    console.error('❌ Migration failed:', error.sqlMessage || error.message);
    if (error.sql) {
      console.error('Failing SQL near:', error.sql.slice(0, 300));
    }
    process.exit(1);
  } finally {
    await connection.end();
  }
}

migrate();
