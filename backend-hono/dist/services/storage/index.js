import { LocalStorageDriver } from './local.storage.js';
import { S3StorageDriver } from './s3.storage.js';
import { env } from '../../config/env.js';
export * from './storage.interface.js';
let storageInstance;
export function getStorage() {
    if (!storageInstance) {
        if (env.STORAGE_DRIVER === 's3' && env.S3_ACCESS_KEY_ID && env.S3_SECRET_ACCESS_KEY) {
            storageInstance = new S3StorageDriver();
        }
        else {
            storageInstance = new LocalStorageDriver();
        }
    }
    return storageInstance;
}
