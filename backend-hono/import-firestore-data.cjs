const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function importSql() {
  console.log('🚀 Importing Firestore data from firebase_export.sql into MySQL...');

  const sqlFile = path.join(__dirname, 'firebase_export.sql');
  if (!fs.existsSync(sqlFile)) {
    console.error('❌ firebase_export.sql not found at:', sqlFile);
    process.exit(1);
  }

  const sqlContent = fs.readFileSync(sqlFile, 'utf8');
  const statements = sqlContent
    .split(/;\r?\n/)
    .map(s => s.trim())
    .filter(s => s.length > 0 && !s.startsWith('--'));

  console.log(`Found ${statements.length} SQL statements to execute.`);

  const dbHost = process.env.DB_HOST || '127.0.0.1';
  const dbPort = parseInt(process.env.DB_PORT || '3306', 10);
  const dbUser = process.env.DB_USER || 'u814384925_iter_user';
  const dbPassword = process.env.DB_PASSWORD || 'wkjBgrET&3AU8kqE';
  const dbName = process.env.DB_NAME || 'u814384925_iter_db';

  const connection = await mysql.createConnection({
    host: dbHost,
    port: dbPort,
    user: dbUser,
    password: dbPassword,
    database: dbName,
    multipleStatements: true,
  });

  console.log(`Connected to MySQL: ${dbUser}@${dbHost}:${dbPort}/${dbName}`);

  await connection.query('SET FOREIGN_KEY_CHECKS = 0;');

  let successCount = 0;
  let errorCount = 0;

  for (let i = 0; i < statements.length; i++) {
    const stmt = statements[i];
    try {
      await connection.query(stmt);
      successCount++;
    } catch (err) {
      errorCount++;
      if (err.errno !== 1062) { // ignore duplicate key errors
        console.warn(`Statement ${i + 1} warning: ${err.message}`);
      }
    }
  }

  await connection.query('SET FOREIGN_KEY_CHECKS = 1;');

  console.log(`\n🎉 Import Complete!`);
  console.log(`- Executed statements: ${successCount}`);
  console.log(`- Warnings/Duplicates ignored: ${errorCount}`);

  // Summary counts
  const tables = ['users', 'posts', 'comments', 'events', 'stories', 'chats', 'messages'];
  console.log('\n📊 Verifying row counts:');
  for (const t of tables) {
    try {
      const [rows] = await connection.query(`SELECT count(*) as count FROM \`${t}\``);
      console.log(`  - ${t}: ${rows[0].count} rows`);
    } catch (_) {}
  }

  await connection.end();
  process.exit(0);
}

importSql().catch(err => {
  console.error('Fatal import error:', err);
  process.exit(1);
});
