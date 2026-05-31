// Supabase Edge Function: delete-user-media
//
// Verifies a Firebase ID token, then permanently deletes EVERY storage object
// the caller has ever uploaded — across both buckets — so account
// self-deletion leaves no media behind. The service-role key never leaves the
// server.
//
// A user can only ever delete their OWN files: every path is rooted at the
// verified token's uid (`<bucket>/<uid>/...`), never at client input. There is
// no parameter that lets a caller target another user.
//
// Deploy (dashboard): create a function named `delete-user-media`, paste this
// file, Deploy. It reuses the same secrets as issue-upload-url
// (FIREBASE_PROJECT_ID; SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are injected).

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { jwtVerify, createRemoteJWKSet } from "https://esm.sh/jose@5.9.3";

const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

// Every object a user owns lives under `<bucket>/<uid>/...`. Listing that one
// folder per bucket recursively covers avatars, covers, posts, post videos,
// stories, story videos, and all chat media (images, videos, files, voices) —
// because issue-upload-url roots every path at `<uid>/`.
const BUCKETS = ["avatars", "posts"];

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

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  let deleted = 0;
  try {
    for (const bucket of BUCKETS) {
      // The user's entire tree is `<uid>/...` in each bucket.
      deleted += await deleteFolder(admin, bucket, uid);
    }
  } catch (e) {
    return json(500, { error: "delete failed", detail: String(e), deleted });
  }

  return json(200, { ok: true, deleted });
});

/**
 * Recursively lists and deletes every object under `folder` in `bucket`.
 * Supabase has no "delete folder" primitive — we page through `list()` and
 * delete in batches. Returns the count of objects removed.
 */
async function deleteFolder(
  supabase: SupabaseClient,
  bucket: string,
  folder: string,
): Promise<number> {
  let removed = 0;
  const stack: string[] = [folder];

  while (stack.length > 0) {
    const dir = stack.pop() as string;
    let offset = 0;
    const pageSize = 100;

    for (;;) {
      const { data, error } = await supabase.storage.from(bucket).list(dir, {
        limit: pageSize,
        offset,
      });
      if (error || !data || data.length === 0) break;

      const files: string[] = [];
      for (const entry of data) {
        // A Supabase "folder" placeholder has a null id; a real object has one.
        if (entry.id === null || entry.id === undefined) {
          stack.push(`${dir}/${entry.name}`);
        } else {
          files.push(`${dir}/${entry.name}`);
        }
      }

      if (files.length > 0) {
        const { error: delErr } = await supabase.storage
          .from(bucket)
          .remove(files);
        if (!delErr) removed += files.length;
      }

      if (data.length < pageSize) break;
      offset += pageSize;
    }
  }

  return removed;
}
