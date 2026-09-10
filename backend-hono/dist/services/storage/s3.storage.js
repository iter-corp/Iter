import { S3Client, PutObjectCommand, DeleteObjectCommand, ListObjectsV2Command } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { env } from '../../config/env.js';
export class S3StorageDriver {
    client;
    bucket;
    publicBaseUrl;
    constructor() {
        this.client = new S3Client({
            region: env.S3_REGION,
            endpoint: env.S3_ENDPOINT || undefined,
            credentials: {
                accessKeyId: env.S3_ACCESS_KEY_ID || '',
                secretAccessKey: env.S3_SECRET_ACCESS_KEY || '',
            },
            forcePathStyle: true, // For MinIO and local testing
        });
        this.bucket = env.S3_BUCKET;
        this.publicBaseUrl = (env.S3_PUBLIC_URL || `${env.S3_ENDPOINT}/${this.bucket}`).replace(/\/$/, '');
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
        const command = new PutObjectCommand({
            Bucket: this.bucket,
            Key: filePath,
        });
        const uploadUrl = await getSignedUrl(this.client, command, { expiresIn: 900 });
        const publicUrl = `${this.publicBaseUrl}/${filePath}`;
        return {
            uploadUrl,
            publicUrl,
            path: filePath,
        };
    }
    async uploadDirect(params) {
        await this.client.send(new PutObjectCommand({
            Bucket: this.bucket,
            Key: params.path,
            Body: params.buffer,
            ContentType: params.contentType,
        }));
        const publicUrl = `${this.publicBaseUrl}/${params.path}`;
        return { publicUrl, path: params.path };
    }
    async deleteFile(bucket, filePath) {
        await this.client.send(new DeleteObjectCommand({
            Bucket: this.bucket,
            Key: filePath,
        }));
    }
    async deleteUserMedia(uid) {
        let deletedCount = 0;
        try {
            const listCommand = new ListObjectsV2Command({
                Bucket: this.bucket,
                Prefix: `${uid}/`,
            });
            const listed = await this.client.send(listCommand);
            if (listed.Contents) {
                for (const item of listed.Contents) {
                    if (item.Key) {
                        await this.deleteFile(this.bucket, item.Key);
                        deletedCount++;
                    }
                }
            }
        }
        catch (e) {
            console.error('Error deleting user S3 media:', e);
        }
        return { deletedCount };
    }
}
