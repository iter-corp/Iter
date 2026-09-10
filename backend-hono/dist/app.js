import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { swaggerUI } from '@hono/swagger-ui';
import { errorHandler } from './middleware/error-handler.js';
import { env } from './config/env.js';
import path from 'path';
import fs from 'fs';
// Routes
import { authRoutes } from './routes/auth.js';
import { userRoutes } from './routes/users.js';
import { postRoutes } from './routes/posts.js';
import { commentRoutes } from './routes/comments.js';
import { storyRoutes } from './routes/stories.js';
import { chatRoutes } from './routes/chats.js';
import { eventRoutes } from './routes/events.js';
import { pollRoutes } from './routes/polls.js';
import { notificationRoutes } from './routes/notifications.js';
import { storageRoutes } from './routes/storage.js';
import { dynamicRoutes } from './routes/dynamic.js';
import { aiRoutes } from './routes/ai.js';
import { adminRoutes } from './routes/admin.js';
export const app = new Hono();
// Global Middleware
app.use('*', logger());
app.use('*', cors({
    origin: env.CORS_ORIGIN === '*' ? '*' : env.CORS_ORIGIN.split(','),
    allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Content-Type', 'Authorization', 'x-firebase-token', 'apikey'],
    exposeHeaders: ['Content-Length', 'Retry-After'],
    maxAge: 600,
}));
// Health Check
app.get('/health', (c) => {
    return c.json({
        status: 'ok',
        uptime: process.uptime(),
        timestamp: new Date().toISOString(),
        environment: env.NODE_ENV,
    });
});
// Local file serving for uploads directory
app.get('/uploads/:bucket/*', async (c) => {
    const bucket = c.req.param('bucket');
    const filePath = c.req.path.replace(`/uploads/${bucket}/`, '');
    const localTarget = path.resolve(env.STORAGE_LOCAL_DIR, bucket, filePath);
    try {
        const stat = await fs.promises.stat(localTarget);
        if (!stat.isFile())
            return c.text('Not a file', 404);
        const ext = path.extname(localTarget).toLowerCase();
        const mimeTypes = {
            '.jpg': 'image/jpeg',
            '.jpeg': 'image/jpeg',
            '.png': 'image/png',
            '.webp': 'image/webp',
            '.gif': 'image/gif',
            '.mp4': 'video/mp4',
            '.mov': 'video/quicktime',
            '.m4a': 'audio/mp4',
            '.mp3': 'audio/mpeg',
            '.pdf': 'application/pdf',
        };
        const contentType = mimeTypes[ext] || 'application/octet-stream';
        const buffer = await fs.promises.readFile(localTarget);
        return c.body(buffer, 200, {
            'Content-Type': contentType,
            'Cache-Control': 'public, max-age=31536000, immutable',
        });
    }
    catch {
        return c.text('File not found', 404);
    }
});
// Mount API v1 Routes
app.route('/api/v1/auth', authRoutes);
app.route('/api/v1/users', userRoutes);
app.route('/api/v1/posts', postRoutes);
app.route('/api/v1/comments', commentRoutes);
app.route('/api/v1/stories', storyRoutes);
app.route('/api/v1/chats', chatRoutes);
app.route('/api/v1/events', eventRoutes);
app.route('/api/v1/polls', pollRoutes);
app.route('/api/v1/notifications', notificationRoutes);
app.route('/api/v1/storage', storageRoutes);
app.route('/api/v1/dynamic', dynamicRoutes);
app.route('/api/v1/ai', aiRoutes);
app.route('/api/v1/admin', adminRoutes);
// OpenAPI JSON Specification
app.get('/api-spec.json', (c) => {
    return c.json({
        openapi: '3.0.0',
        info: {
            title: 'Coil / Iter Backend API',
            version: '1.0.0',
            description: 'Extensible Server-Driven Backend replacing Firebase & Supabase',
        },
        servers: [{ url: env.APP_URL }],
        paths: {
            '/health': { get: { summary: 'System health check' } },
            '/api/v1/auth/signup': { post: { summary: 'Register with email and password' } },
            '/api/v1/auth/login': { post: { summary: 'Login with email and password' } },
            '/api/v1/dynamic/config': { get: { summary: 'Fetch remote feature flags and version gate' } },
            '/api/v1/dynamic/screens/{screenId}': { get: { summary: 'Get Server-Driven UI (SDUI) layout schema' } },
            '/api/v1/posts': { get: { summary: 'Stream feed posts' }, post: { summary: 'Create new post' } },
            '/api/v1/chats/conversations': { get: { summary: 'Get user conversations inbox' } },
            '/api/v1/storage/upload-url': { post: { summary: 'Issue upload target for media file' } },
            '/api/v1/ai/translate': { post: { summary: 'Translate text with multi-provider fallback' } },
        },
    });
});
// Interactive Swagger UI documentation
app.get('/docs', swaggerUI({ url: '/api-spec.json' }));
// Global Error Handler
app.onError(errorHandler);
