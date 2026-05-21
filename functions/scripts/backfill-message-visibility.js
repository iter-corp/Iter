/*
 * Backfills legacy chat message docs with visibleToUids.
 *
 * For each message missing visibleToUids:
 * - If message is profanity sender-only (visibility == 'sender_only' or
 *   profanityFiltered == true), set visibleToUids = [senderUid].
 * - Otherwise set visibleToUids to all chat participants.
 *
 * Run (PowerShell):
 *   cd functions
 *   node scripts/backfill-message-visibility.js --project coil-50528 --credentials .\service-account.json
 */

const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

const args = process.argv.slice(2);
function flag(name) {
  const i = args.indexOf(name);
  return i !== -1 ? args[i + 1] : undefined;
}

const projectId =
  flag("--project") ||
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT;
const credentialsPath = flag("--credentials");

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

async function backfillChat(chatDoc) {
  const chatId = chatDoc.id;
  const chatData = chatDoc.data() || {};
  const participants = Array.isArray(chatData.participants)
    ? chatData.participants.map((v) => String(v)).filter((v) => v.length > 0)
    : [];

  let updated = 0;
  let lastDoc = null;

  while (true) {
    let q = db
      .collection("chats")
      .doc(chatId)
      .collection("messages")
      .orderBy("__name__")
      .limit(300);
    if (lastDoc) q = q.startAfter(lastDoc);

    const snap = await q.get();
    if (snap.empty) break;

    const batch = db.batch();
    let writes = 0;

    for (const doc of snap.docs) {
      const m = doc.data() || {};
      if (Array.isArray(m.visibleToUids) && m.visibleToUids.length > 0) {
        continue;
      }

      const senderUid = String(m.senderUid || "");
      const isSenderOnly =
        String(m.visibility || "") === "sender_only" ||
        m.profanityFiltered === true;

      const visibleToUids = isSenderOnly
        ? senderUid
          ? [senderUid]
          : participants
        : participants;

      batch.set(
        doc.ref,
        {
          visibleToUids,
        },
        { merge: true },
      );
      writes += 1;
      updated += 1;
    }

    if (writes > 0) {
      await batch.commit();
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < 300) break;
  }

  return updated;
}

async function main() {
  const chats = await db.collection("chats").get();
  let totalUpdated = 0;

  for (const chat of chats.docs) {
    const n = await backfillChat(chat);
    if (n > 0) {
      console.log(`chat ${chat.id}: updated ${n} messages`);
    }
    totalUpdated += n;
  }

  console.log(
    `Done. Backfilled visibleToUids on ${totalUpdated} message docs.`,
  );
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
