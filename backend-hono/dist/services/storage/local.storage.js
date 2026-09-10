import fs from 'fs/promises';
import path from 'path';
import { env } from '../../config/env.js';
export class LocalStorageDriver {
    baseDir;
    publicBaseUrl;
    constructor() {
        this.baseDir = path.resolve(env.STORAGE_LOCAL_DIR);
        this.publicBaseUrl = env.STORAGE_PUBLIC_URL.replace(/\/$/, '');
    }
    resolvePath(bucket, filePath) {
        return path.join(this.baseDir, bucket, filePath);
    }
    buildPath(kind, uid, ext, subPath) {
        const ts = Date.now();
        const rand = Math.random().toString(36).substring(2, 10);
        const cleanExt = ext.replace(/^\./, '').toLowerCase();
        switch (kind) {
            case 'avatar':
                return `${uid}/avatar_${ts}.${cleanExt}`;
            case 'cover':
                return `${uid}/cover_${ts}.${cleanExt}`;
            case 'post':
                return `${uid}/posts/${ts}_${rand}.${cleanExt}`;
            case 'post-video':
                return `${uid}/posts/videos/${ts}_${rand}.${cleanExt}`;
            case 'story':
                return `${uid}/stories/${ts}_${rand}.${cleanExt}`;
            case 'story-video':
                return `${uid}/stories/videos/${ts}_${rand}.${cleanExt}`;
            case 'chat':
                return `${uid}/chats/${subPath || 'general'}/${ts}_${rand}.${cleanExt}`;
            case 'chat-video':
                return `${uid}/chats/${subPath || 'general'}/videos/${ts}_${rand}.${cleanExt}`;
            case 'chat-file':
                return `${uid}/chats/${subPath || 'general'}/files/${ts}_${rand}.${cleanExt}`;
            case 'audio':
                return `${uid}/chats/${subPath || 'general'}/voices/${ts}_${rand}.${cleanExt}`;
            default:
                return `${uid}/misc/${ts}_${rand}.${cleanExt}`;
        }
    }
    async issueUploadUrl(params) {
        const filePath = this.buildPath(params.kind, params.uid, params.ext, params.subPath);
        const uploadTarget = `${env.APP_URL}/api/v1/storage/upload-direct?bucket=${encodeURIComponent(params.bucket)}&path=${encodeURIComponent(filePath)}`;
        const publicUrl = `${this.publicBaseUrl}/${params.bucket}/${filePath}`;
        return {
            uploadUrl: uploadTarget,
            publicUrl,
            path: filePath,
        };
    }
    async uploadDirect(params) {
        const fullPath = this.resolvePath(params.bucket, params.path);
        await fs.mkdir(path.dirname(fullPath), { recursive: true });
        await fs.writeFile(fullPath, params.buffer);
        const publicUrl = `${this.publicBaseUrl}/${params.bucket}/${params.path}`;
        return { publicUrl, path: params.path };
    }
    async deleteFile(bucket, filePath) {
        try {
            const fullPath = this.resolvePath(bucket, filePath);
            await fs.unlink(fullPath);
        }
        catch {
            // Ignore if file doesn't exist
        }
    }
    async deleteUserMedia(uid) {
        let deletedCount = 0;
        const buckets = ['avatars', 'posts'];
        for (const bucket of buckets) {
            const userDir = path.join(this.baseDir, bucket, uid);
            try {
                await fs.rm(userDir, { recursive: true, force: true });
                deletedCount++;
            }
            catch {
                // Ignore if user directory doesn't exist
            }
        }
        return { deletedCount };
    }
}
