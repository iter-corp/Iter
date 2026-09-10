import { migrate } from 'drizzle-orm/postgres-js/migrator';
import { db, client } from './index.js';
export async function runMigrations() {
    console.log('⏳ Running database migrations...');
    try {
        await migrate(db, { migrationsFolder: './src/db/migrations' });
        console.log('✅ Migrations completed successfully.');
    }
    catch (error) {
        console.error('❌ Migration failed:', error);
        throw error;
    }
    finally {
        await client.end();
    }
}
if (process.argv[1]?.includes('migrate.ts')) {
    runMigrations()
        .then(() => process.exit(0))
        .catch(() => process.exit(1));
}
