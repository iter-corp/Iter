import { migrate } from 'drizzle-orm/mysql2/migrator';
import { db, poolConnection } from './index.js';
export async function runMigrations() {
    console.log('⏳ Running database migrations on MySQL...');
    try {
        await migrate(db, { migrationsFolder: './src/db/migrations' });
        console.log('✅ Migrations completed successfully.');
    }
    catch (error) {
        console.error('❌ Migration failed:', error);
        throw error;
    }
    finally {
        await poolConnection.end();
    }
}
if (process.argv[1]?.includes('migrate.ts')) {
    runMigrations()
        .then(() => process.exit(0))
        .catch(() => process.exit(1));
}
