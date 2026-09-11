import { drizzle } from 'drizzle-orm/mysql2';
import mysql from 'mysql2/promise';
import * as schema from './schema/index.js';
import { env } from '../config/env.js';

// Connection pool configuration
export const poolConnection = mysql.createPool({
  uri: env.DATABASE_URL,
  waitForConnections: true,
  connectionLimit: 20,
  queueLimit: 0,
});

export const db = drizzle(poolConnection, { schema, mode: 'default' });
export type Database = typeof db;

