const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function migrate() {
  console.log('⏳ Running direct database migrations...');

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
