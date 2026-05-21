/*
 * Seeds the English profanity list into Firestore at:
 *   adminConfig/app.profanityWordsEn
 *
 * Run (PowerShell):
 *   cd functions
 *   node scripts/seed-profanity.js --project coil-50528 --credentials .\service-account.json
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

const PROFANITY_WORDS_EN = [
  "arse",
  "asshole",
  "bastard",
  "bitch",
  "bloody",
  "bollocks",
  "bullshit",
  "crap",
  "damn",
  "dick",
  "freaking",
  "fuck",
  "fucker",
  "fucking",
  "goddamn",
  "hell",
  "motherfucker",
  "piss",
  "prick",
  "shit",
  "slut",
  "whore",
  "wanker",
].sort();

async function main() {
  await db.collection("adminConfig").doc("app").set(
    {
      profanityWordsEn: PROFANITY_WORDS_EN,
      profanityWordsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  console.log(
    `Saved ${PROFANITY_WORDS_EN.length} English profanity words to adminConfig/app.profanityWordsEn`,
  );
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
