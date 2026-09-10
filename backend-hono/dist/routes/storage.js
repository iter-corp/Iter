import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { getStorage } from '../services/storage/index.js';
import { requireAuth } from '../middleware/auth.js';
import { AppError } from '../middleware/error-handler.js';
export const storageRoutes = new Hono();
// Allowed buckets and file formats
const ALLOWED_BUCKETS = new Set(['avatars', 'posts']);
const ALLOWED_EXTS = new Set([
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic',
    'm4a', 'aac', 'mp3', 'wav', 'ogg',
    'mp4', 'mov', 'webm', 'm4v', '3gp',
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'csv', 'zip',
]);
// ── 1. Issue Upload URL ─────────────────────────────────────────────────────
const issueUploadUrlSchema = z.object({
    bucket: z.string(),
    kind: z.string(),
    ext: z.string(),
    subPath: z.string().optional(),
});
storageRoutes.post('/upload-url', requireAuth, zValidator('json', issueUploadUrlSchema), async (c) => {
    const uid = c.get('uid');
    const { bucket, kind, ext, subPath } = c.req.valid('json');
    const cleanExt = ext.replace(/^\./, '').toLowerCase();
    if (!ALLOWED_BUCKETS.has(bucket)) {
        throw new AppError(`Invalid bucket "${bucket}". Allowed: avatars, posts`, 400, 'INVALID_BUCKET');
    }
    if (!ALLOWED_EXTS.has(cleanExt)) {
        throw new AppError(`File extension "${cleanExt}" is not allowed`, 400, 'INVALID_EXTENSION');
    }
    const storage = getStorage();
    const result = await storage.issueUploadUrl({
        bucket,
        kind,
        ext: cleanExt,
        subPath,
        uid,
    });
    return c.json(result);
});
// ── 2. Direct Upload Handler (for Local Driver or fallback) ─────────────────
storageRoutes.put('/upload-direct', requireAuth, async (c) => {
    const bucket = c.req.query('bucket');
    const filePath = c.req.query('path');
    const uid = c.get('uid');
    if (!bucket || !filePath) {
        throw new AppError('Missing bucket or path query parameters', 400, 'INVALID_REQUEST');
    }
    // Security: ensure path starts with the user's UID
    if (!filePath.startsWith(`${uid}/`)) {
        throw new AppError('Forbidden upload target path', 403, 'PATH_TAMPERING');
    }
    const contentType = c.req.header('content-type') || 'application/octet-stream';
    const arrayBuffer = await c.req.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);
    const storage = getStorage();
    const uploaded = await storage.uploadDirect({
        bucket,
        path: filePath,
        buffer,
        contentType,
    });
    return c.json({ success: true, ...uploaded });
});
// ── 3. Delete All User Media (Self-Delete / Account Cleanup) ─────────────────
storageRoutes.post('/delete-user-media', requireAuth, async (c) => {
    const uid = c.get('uid');
    const storage = getStorage();
    const result = await storage.deleteUserMedia(uid);
    return c.json({ success: true, ...result });
});
