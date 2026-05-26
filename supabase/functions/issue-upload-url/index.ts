// Supabase Edge Function: issue-upload-url
// Verifies a Firebase ID token and returns a signed Supabase Storage upload URL
// scoped to the user's own folder inside the requested bucket.
//
// Request body: { bucket: 'avatars' | 'posts', kind: 'avatar'|'cover'|'post'|'post-video'|'story'|'story-video'|'chat'|'chat-video'|'chat-file'|'audio', ext: string, subPath?: string }
// Response:     { uploadUrl, token, path, publicUrl }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { jwtVerify, createRemoteJWKSet } from "https://esm.sh/jose@5.9.3";

const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const ALLOWED_BUCKETS = new Set(["avatars", "posts"]);
const IMAGE_EXTS = new Set(["jpg", "jpeg", "png", "webp", "gif", "heic"]);
const AUDIO_EXTS = new Set(["m4a", "aac", "mp3", "wav", "ogg"]);
const VIDEO_EXTS = new Set(["mp4", "mov", "webm", "m4v", "3gp"]);
const DOC_EXTS = new Set([
  "pdf", "doc", "docx", "xls", "xlsx",
  "ppt", "pptx", "txt", "rtf", "csv", "zip",
]);
const ALLOWED_EXTS = new Set([
  ...IMAGE_EXTS,
  ...AUDIO_EXTS,
  ...VIDEO_EXTS,
  ...DOC_EXTS,
]);

const JWKS = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  ),
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-firebase-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { error: "method not allowed" });
  }

  // Firebase ID token arrives in a separate header so the standard
  // Authorization header can carry Supabase's anon key (which their
  // gateway validates before hitting this function).
  const token = req.headers.get("x-firebase-token") ?? "";
  if (!token) return json(401, { error: "missing x-firebase-token header" });

  let uid: string;
  try {
    const { payload } = await jwtVerify(token, JWKS, {
      issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
      audience: FIREBASE_PROJECT_ID,
    });
    uid = payload.sub as string;
    if (!uid) throw new Error("no sub claim");
  } catch (e) {
    return json(401, { error: "invalid firebase token", detail: String(e) });
  }

  let body: { bucket?: string; kind?: string; ext?: string; subPath?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid json body" });
  }

  const bucket = String(body.bucket ?? "");
  const kind = String(body.kind ?? "");
  const ext = String(body.ext ?? "").toLowerCase();
  const subPath = body.subPath ? String(body.subPath) : null;

  if (!ALLOWED_BUCKETS.has(bucket)) return json(400, { error: "bad bucket" });
  if (!ALLOWED_EXTS.has(ext)) return json(400, { error: "bad ext" });

  // Build path. Folder always starts with uid so RLS policies can scope.
  let path: string;
  const ts = Date.now();
  const rand = Math.random().toString(36).slice(2, 10);
  if (kind === "avatar") {
    path = `${uid}/avatar_${ts}.${ext}`;
  } else if (kind === "cover") {
    path = `${uid}/cover_${ts}.${ext}`;
  } else if (kind === "post") {
    path = `${uid}/posts/${ts}_${rand}.${ext}`;
  } else if (kind === "post-video") {
    if (!VIDEO_EXTS.has(ext)) {
      return json(400, { error: "post-video kind requires video ext" });
    }
    path = `${uid}/posts/videos/${ts}_${rand}.${ext}`;
  } else if (kind === "story") {
    path = `${uid}/stories/${ts}_${rand}.${ext}`;
  } else if (kind === "story-video") {
    if (!VIDEO_EXTS.has(ext)) {
      return json(400, { error: "story-video kind requires video ext" });
    }
    path = `${uid}/stories/videos/${ts}_${rand}.${ext}`;
  } else if (kind === "chat" && subPath) {
    // Only allow alphanumeric + underscore in chatId
    if (!/^[A-Za-z0-9_]+$/.test(subPath)) {
      return json(400, { error: "bad subPath" });
    }
    path = `${uid}/chats/${subPath}/${ts}_${rand}.${ext}`;
  } else if (kind === "chat-video" && subPath) {
    if (!/^[A-Za-z0-9_]+$/.test(subPath)) {
      return json(400, { error: "bad subPath" });
    }
    if (!VIDEO_EXTS.has(ext)) {
      return json(400, { error: "chat-video kind requires video ext" });
    }
    path = `${uid}/chats/${subPath}/videos/${ts}_${rand}.${ext}`;
  } else if (kind === "chat-file" && subPath) {
    if (!/^[A-Za-z0-9_]+$/.test(subPath)) {
      return json(400, { error: "bad subPath" });
    }
    if (!DOC_EXTS.has(ext)) {
      return json(400, { error: "chat-file kind requires document ext" });
    }
    path = `${uid}/chats/${subPath}/files/${ts}_${rand}.${ext}`;
  } else if (kind === "audio" && subPath) {
    // Voice messages live alongside chat media but in a /voices/ folder
    // so they're easy to enumerate separately.
    if (!/^[A-Za-z0-9_]+$/.test(subPath)) {
      return json(400, { error: "bad subPath" });
    }
    if (!AUDIO_EXTS.has(ext)) {
      return json(400, { error: "audio kind requires audio ext" });
    }
    path = `${uid}/chats/${subPath}/voices/${ts}_${rand}.${ext}`;
  } else {
    return json(400, { error: "bad kind" });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data, error } = await admin.storage
    .from(bucket)
    .createSignedUploadUrl(path);

  if (error) return json(500, { error: "sign failed", detail: error.message });

  const publicUrl =
    admin.storage.from(bucket).getPublicUrl(path).data.publicUrl;

  return json(200, {
    uploadUrl: data.signedUrl,
    token: data.token,
    path,
    publicUrl,
  });
});
