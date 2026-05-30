/*
 * Migrates legacy chat voice messages whose stored object is named `.aac`.
 *
 * Background: older voice notes were uploaded with a `.aac` filename even
 * though the bytes are an MP4/AAC container (`.m4a`). Mobile audio players key
 * off the `.aac` URL extension and parse them as a raw ADTS stream, so they
 * play silently. The app now stores new notes as `.m4a`; this script fixes the
 * old ones by copying each `.aac` object to a `.m4a` object (with the correct
 * `audio/mp4` content-type) and updating the message's `voiceUrl` in Firestore.
 *
 * It is idempotent: messages already pointing at `.m4a` are skipped, and the
 * copy uses upsert so a re-run is safe.
 *
 * Run (PowerShell):
 *   cd functions
 *   $env:SUPABASE_URL="https://xxxx.supabase.co"
 *   $env:SUPABASE_SERVICE_ROLE_KEY="<service-role-key>"
 *   node scripts/migrate-voice-aac-to-m4a.js --project coil-50528 --credentials .\service-account.json
 *
 * Add --dry-run to list what would change without writing anything.
 */

const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

const args = process.argv.slice(2);
function flag(name) {
  const i = args.indexOf(name);
  return i !== -1 ? args[i + 1] : undefined;
}
const hasFlag = (name) => args.includes(name);

const projectId =
  flag("--project") ||
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT;
const credentialsPath = flag("--credentials");
const dryRun = hasFlag("--dry-run");

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BUCKET = "posts"; // voice objects live in the posts bucket

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error(
    "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY env vars before running.",
  );
  process.exit(1);
}

if (credentialsPath) {
  const resolved = path.resolve(credentialsPath);
  if (!fs.existsSync(resolved)) {
    console.error(`Credentials file not found: ${resolved}`);
    process.exit(1);
  }
  const serviceAccount = JSON.parse(fs.readFileSync(resolved, "utf8"));
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: projectId || serviceAccount.project_id,
  });
} else {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();

const PUBLIC_PREFIX = `${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Runs a Firestore read with exponential backoff on transient quota errors
 * (code 8 = RESOURCE_EXHAUSTED). On the free tier the daily read quota can be
 * exhausted entirely — in that case backing off won't help and the error is
 * rethrown after the last attempt so the operator knows to wait/upgrade.
 */
async function withRetry(fn, attempts = 5) {
  let delay = 2000;
  for (let i = 0; i < attempts; i += 1) {
    try {
      return await fn();
    } catch (e) {
      if (e && e.code === 8 && i < attempts - 1) {
        console.warn(
          `  quota exceeded, backing off ${delay}ms (attempt ${i + 1}/${attempts})…`,
        );
        await sleep(delay);
        delay *= 2;
        continue;
      }
      throw e;
    }
  }
}

/** Strips the public-URL prefix + query string to get the storage path. */
function storagePathFromUrl(url) {
  if (!url.startsWith(PUBLIC_PREFIX)) return null;
  let rest = url.slice(PUBLIC_PREFIX.length);
  const q = rest.indexOf("?");
  if (q !== -1) rest = rest.slice(0, q);
  return decodeURIComponent(rest);
}

function isLegacyAac(url) {
  if (typeof url !== "string") return false;
  const q = url.indexOf("?");
  const clean = (q === -1 ? url : url.slice(0, q)).toLowerCase();
  return clean.endsWith(".aac");
}

/** Download an object's bytes via the Storage API (service role). */
async function downloadObject(srcPath) {
  const url = `${SUPABASE_URL}/storage/v1/object/${BUCKET}/${srcPath}`;
  const resp = await fetch(url, {
    headers: {
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      apikey: SERVICE_ROLE_KEY,
    },
  });
  if (!resp.ok) {
    throw new Error(`download ${srcPath} failed: ${resp.status}`);
  }
  return Buffer.from(await resp.arrayBuffer());
}

/** Upload bytes to a new path with the correct content-type (upsert). */
async function uploadObject(destPath, bytes) {
  const url = `${SUPABASE_URL}/storage/v1/object/${BUCKET}/${destPath}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      apikey: SERVICE_ROLE_KEY,
      "Content-Type": "audio/mp4",
      "x-upsert": "true",
    },
    body: bytes,
  });
  if (!resp.ok && resp.status !== 200 && resp.status !== 201) {
    const body = await resp.text();
    throw new Error(`upload ${destPath} failed: ${resp.status} ${body}`);
  }
}

function publicUrlFor(destPath) {
  return `${PUBLIC_PREFIX}${destPath
    .split("/")
    .map(encodeURIComponent)
    .join("/")}`;
}

async function migrateMessage(doc) {
  const m = doc.data() || {};
  const url = m.voiceUrl;
  if (!isLegacyAac(url)) return false;

  const srcPath = storagePathFromUrl(url);
  if (!srcPath) {
    console.warn(`  skip ${doc.ref.path}: unrecognized URL ${url}`);
    return false;
  }
  const destPath = srcPath.replace(/\.aac$/i, ".m4a");
  const newUrl = publicUrlFor(destPath);

  if (dryRun) {
    console.log(`  [dry-run] ${srcPath} -> ${destPath}`);
    return true;
  }

  const bytes = await downloadObject(srcPath);
  await uploadObject(destPath, bytes);
  await doc.ref.set({ voiceUrl: newUrl }, { merge: true });
  console.log(`  migrated ${doc.ref.path}`);
  return true;
}

async function migrateChat(chatDoc) {
  const chatId = chatDoc.id;
  let migrated = 0;
  let lastDoc = null;

  while (true) {
    let q = db
      .collection("chats")
      .doc(chatId)
      .collection("messages")
      .orderBy("__name__")
      .limit(300);
    if (lastDoc) q = q.startAfter(lastDoc);

    const snap = await withRetry(() => q.get());
    if (snap.empty) break;

    for (const doc of snap.docs) {
      try {
        if (await migrateMessage(doc)) migrated += 1;
      } catch (e) {
        console.error(`  ERROR ${doc.ref.path}: ${e.message}`);
      }
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < 300) break;
  }

  return migrated;
}

async function main() {
  let total = 0;
  let processedChats = 0;
  let lastChat = null;

  // Paginate the chats collection (instead of one big .get()) so we stay well
  // under Firestore read quotas and the run is gentler / resumable.
  while (true) {
    let q = db.collection("chats").orderBy("__name__").limit(50);
    if (lastChat) q = q.startAfter(lastChat);

    const snap = await withRetry(() => q.get());
    if (snap.empty) break;

    for (const chat of snap.docs) {
      const n = await migrateChat(chat);
      if (n > 0) console.log(`chat ${chat.id}: migrated ${n} voice messages`);
      total += n;
      processedChats += 1;
    }

    lastChat = snap.docs[snap.docs.length - 1];
    if (snap.size < 50) break;
  }

  console.log(
    `Done. Scanned ${processedChats} chats. ${dryRun ? "Would migrate" : "Migrated"} ${total} legacy .aac voice messages.`,
  );
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
