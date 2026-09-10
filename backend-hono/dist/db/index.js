import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from './schema/index.js';
import { env } from '../config/env.js';
// Connection pool configuration
const connectionString = env.DATABASE_URL;
// For migrations and normal operations
export const client = postgres(connectionString, {
    max: 20,
    idle_timeout: 30,
    connect_timeout: 10,
});
export const db = drizzle(client, { schema });
