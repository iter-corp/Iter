import { z } from 'zod';
import * as dotenv from 'dotenv';
dotenv.config();
const envSchema = z.object({
    NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
    PORT: z.coerce.number().default(3000),
    HOST: z.string().default('0.0.0.0'),
    APP_URL: z.string().default('http://localhost:3000'),
    CORS_ORIGIN: z.string().default('*'),
    DATABASE_URL: z.string().default('postgres://postgres:postgres@localhost:5432/iter_db'),
    JWT_SECRET: z.string().min(16).default('iter_default_jwt_secret_change_in_production_32char'),
    JWT_ACCESS_EXPIRATION: z.string().default('15m'),
    JWT_REFRESH_EXPIRATION: z.string().default('30d'),
    STORAGE_DRIVER: z.enum(['local', 's3']).default('local'),
    STORAGE_LOCAL_DIR: z.string().default('./uploads'),
    STORAGE_PUBLIC_URL: z.string().default('http://localhost:3000/uploads'),
    S3_ENDPOINT: z.string().optional(),
    S3_REGION: z.string().default('auto'),
    S3_BUCKET: z.string().default('iter-media'),
    S3_ACCESS_KEY_ID: z.string().optional(),
    S3_SECRET_ACCESS_KEY: z.string().optional(),
    S3_PUBLIC_URL: z.string().optional(),
    FIREBASE_SERVICE_ACCOUNT_KEY: z.string().optional(),
    GEMINI_API_KEY: z.string().optional(),
    OPENAI_API_KEY: z.string().optional(),
    ANTHROPIC_API_KEY: z.string().optional(),
    AZURE_TRANSLATOR_KEY: z.string().optional(),
    AZURE_TRANSLATOR_REGION: z.string().optional(),
    NASA_API_KEY: z.string().default('DEMO_KEY'),
    AGORA_APP_ID: z.string().optional(),
    AGORA_APP_CERTIFICATE: z.string().optional(),
});
export const env = envSchema.parse(process.env);
