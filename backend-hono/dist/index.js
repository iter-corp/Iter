import { serve } from '@hono/node-server';
import { app } from './app.js';
import { env } from './config/env.js';
import { realtimeService } from './services/websocket.service.js';
import { initFirebase } from './services/fcm.service.js';
import fs from 'fs/promises';
import path from 'path';
async function bootstrap() {
    // Ensure local upload storage directory exists
    if (env.STORAGE_DRIVER === 'local') {
        const uploadDir = path.resolve(env.STORAGE_LOCAL_DIR);
        await fs.mkdir(path.join(uploadDir, 'avatars'), { recursive: true });
        await fs.mkdir(path.join(uploadDir, 'posts'), { recursive: true });
    }
    // Initialize Firebase Admin for FCM push notifications
    initFirebase();
    // Start HTTP server with Node adapter
    const server = serve({
        fetch: app.fetch,
        port: env.PORT,
        hostname: env.HOST,
    }, (info) => {
        console.log(`🚀 Iter Hono Backend running on http://${info.address}:${info.port}`);
        console.log(`📖 Interactive API documentation available at http://${info.address}:${info.port}/docs`);
    });
    // Initialize WebSocket server on the same HTTP instance
    realtimeService.init(server);
}
bootstrap().catch((err) => {
    console.error('Fatal bootstrap error:', err);
    process.exit(1);
});
