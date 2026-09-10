export interface UploadUrlResult {
  uploadUrl: string;
  publicUrl: string;
  token?: string;
  path: string;
}

export interface StorageDriver {
  issueUploadUrl(params: {
    bucket: string;
    kind: string;
    ext: string;
    subPath?: string;
    uid: string;
  }): Promise<UploadUrlResult>;

  uploadDirect(params: {
    bucket: string;
    path: string;
    buffer: Buffer;
    contentType: string;
  }): Promise<{ publicUrl: string; path: string }>;

  deleteFile(bucket: string, path: string): Promise<void>;

  deleteUserMedia(uid: string): Promise<{ deletedCount: number }>;
}
