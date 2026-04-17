/*
 * Seeds Firestore with sample Users and Events so the Connect/Events screens
 * have real data to test against.
 *
 * ─────────────────────────────────────────────────────────
 * Get a service-account key (one time)
 * ─────────────────────────────────────────────────────────
 *   1. Firebase Console → Project settings → Service accounts
 *   2. Click "Generate new private key" → download the JSON
 *   3. Save it somewhere safe (e.g. functions/service-account.json)
 *      NOTE: this file is secret — do NOT commit it.
 *
 * ─────────────────────────────────────────────────────────
 * Run (PowerShell)
 * ─────────────────────────────────────────────────────────
 *   cd functions
 *   node scripts/seed.js --project coil-50528 --credentials .\service-account.json
 *
 * Clean up:
 *   node scripts/seed.js --project coil-50528 --credentials .\service-account.json --delete
 *
 * Re-running is safe: upserts to deterministic IDs (seed_user_01 … seed_event_06).
 */

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

const args = process.argv.slice(2);
function flag(name) {
  const i = args.indexOf(name);
  return i !== -1 ? args[i + 1] : undefined;
}
const projectId =
  flag('--project') ||
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT;
const credentialsPath = flag('--credentials');
const shouldDelete = args.includes('--delete');

// If --credentials is passed, use that explicit service account — bypasses any
// stale GOOGLE_APPLICATION_CREDENTIALS env var pointing at a nonexistent file.
if (credentialsPath) {
  const resolved = path.resolve(credentialsPath);
  if (!fs.existsSync(resolved)) {
    console.error(`Credentials file not found: ${resolved}`);
    process.exit(1);
  }
  const serviceAccount = JSON.parse(fs.readFileSync(resolved, 'utf8'));
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: projectId || serviceAccount.project_id,
  });
} else {
  // Fall back to Application Default Credentials (gcloud auth application-default login
  // or GOOGLE_APPLICATION_CREDENTIALS env var).
  admin.initializeApp({ projectId });
}

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;

const now = new Date();
const daysAgo = (n) => Timestamp.fromDate(new Date(now.getTime() - n * 86400000));

// ─────────────────────────────────────────────────────────
// Sample users
// ─────────────────────────────────────────────────────────
const USERS = [
  {
    id: 'seed_user_01',
    username: 'Lila',
    handle: '@lila_fr',
    avatarUrl: 'https://i.pravatar.cc/300?img=47',
    bio: 'Paris-based designer learning Japanese. Coffee addict.',
    postsCount: 12,
    followersCount: 340,
    followingCount: 182,
    city: 'Paris',
    gender: 'Female',
    location: { lat: 48.8566, lng: 2.3522 },
    createdAt: daysAgo(28),
  },
  {
    id: 'seed_user_02',
    username: 'Valentin',
    handle: '@val_fr',
    avatarUrl: 'https://i.pravatar.cc/300?img=12',
    bio: 'Hello! I just want to make new friends around the world and practice my English.',
    postsCount: 4,
    followersCount: 82,
    followingCount: 120,
    city: 'Lyon',
    gender: 'Male',
    location: { lat: 45.7640, lng: 4.8357 },
    createdAt: daysAgo(18),
  },
  {
    id: 'seed_user_03',
    username: 'Malika Reine',
    handle: '@malika',
    avatarUrl: 'https://i.pravatar.cc/300?img=32',
    bio: "Hi, I'm Malika — a novelist. Learning a language goes far beyond words.",
    postsCount: 21,
    followersCount: 1204,
    followingCount: 301,
    city: 'Douala',
    gender: 'Female',
    location: { lat: 4.0511, lng: 9.7679 },
    createdAt: daysAgo(92),
  },
  {
    id: 'seed_user_04',
    username: 'Kira',
    handle: '@kira_キラ',
    avatarUrl: 'https://i.pravatar.cc/300?img=26',
    bio: 'A scholar of life. Progress over perfection.',
    postsCount: 38,
    followersCount: 4210,
    followingCount: 512,
    city: 'Paris',
    gender: 'Non-binary',
    location: { lat: 48.8566, lng: 2.3522 },
    createdAt: daysAgo(220),
  },
  {
    id: 'seed_user_05',
    username: 'Omar',
    handle: '@omar_b',
    avatarUrl: 'https://i.pravatar.cc/300?img=15',
    bio: 'Beirut ↔ Berlin. Product designer, amateur DJ.',
    postsCount: 7,
    followersCount: 160,
    followingCount: 140,
    city: 'Beirut',
    gender: 'Male',
    location: { lat: 33.8938, lng: 35.5018 },
    createdAt: daysAgo(44),
  },
  {
    id: 'seed_user_06',
    username: 'Sana',
    handle: '@sana_sw',
    avatarUrl: 'https://i.pravatar.cc/300?img=44',
    bio: 'Software engineer by day, ceramicist by weekend.',
    postsCount: 2,
    followersCount: 54,
    followingCount: 78,
    city: 'Istanbul',
    gender: 'Female',
    location: { lat: 41.0082, lng: 28.9784 },
    createdAt: daysAgo(9),
  },
  {
    id: 'seed_user_07',
    username: 'Hiro',
    handle: '@hiro_jp',
    avatarUrl: 'https://i.pravatar.cc/300?img=68',
    bio: 'Tokyo photographer. Happy to swap English ↔ Japanese.',
    postsCount: 55,
    followersCount: 9800,
    followingCount: 220,
    city: 'Tokyo',
    gender: 'Male',
    location: { lat: 35.6762, lng: 139.6503 },
    createdAt: daysAgo(410),
  },
  {
    id: 'seed_user_08',
    username: 'Noor',
    handle: '@noor_ae',
    avatarUrl: 'https://i.pravatar.cc/300?img=49',
    bio: 'Dubai. Venture builder, reader, coffee snob.',
    postsCount: 0,
    followersCount: 12,
    followingCount: 20,
    city: 'Dubai',
    gender: 'Female',
    location: { lat: 25.2048, lng: 55.2708 },
    createdAt: daysAgo(2),
  },
];

// ─────────────────────────────────────────────────────────
// Sample events
// ─────────────────────────────────────────────────────────
const EVENTS = [
  {
    id: 'seed_event_01',
    title: 'Harvard University',
    subtitle: '@Psychology Group',
    location: 'Cambridge, MA 02138, USA',
    description:
      'Attend a psychology summit at Harvard University — an incredible experience meeting students and researchers from around the world.',
    phone: '+1 617-495-1000',
    email: 'psych@harvard.edu',
    imageUrls: [
      'https://images.unsplash.com/photo-1523050854058-8df90110c9f1?w=800',
      'https://images.unsplash.com/photo-1541339907198-e08756dedf3f?w=800',
    ],
    createdAt: daysAgo(3),
  },
  {
    id: 'seed_event_02',
    title: 'Mt. Everest',
    subtitle: '@Youth Group',
    location: 'Nepal',
    description:
      'Climb Mount Everest in Nepal — one of the highest mountains in the world at 8,848m. A little difficult but unforgettable.',
    phone: '+977 1-5551212',
    email: 'youth@everest.np',
    imageUrls: [
      'https://images.unsplash.com/photo-1551632811-561732d1e306?w=800',
      'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=800',
    ],
    createdAt: daysAgo(7),
  },
  {
    id: 'seed_event_03',
    title: 'Fine Arts Institute',
    subtitle: '@Creative Arts Club',
    location: 'Rome, Italy',
    description:
      'Explore the Fine Arts Institute in Rome — a vibrant community of creatives working across painting, sculpture, and mixed media.',
    phone: '+39 06 69887115',
    email: 'arts@fai.it',
    imageUrls: [
      'https://images.unsplash.com/photo-1460661419201-fd4cecdf8a8b?w=800',
      'https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800',
    ],
    createdAt: daysAgo(12),
  },
  {
    id: 'seed_event_04',
    title: 'MAC Enterprise Meetup',
    subtitle: '@Meeting Room',
    location: 'Beirut, Lebanon',
    description:
      'Corporate networking at MAC Enterprise — business leaders and entrepreneurs coming together for a day of collaboration.',
    phone: '+961 1-123456',
    email: 'meet@mac.lb',
    imageUrls: [
      'https://images.unsplash.com/photo-1542744173-8e7e53415bb0?w=800',
      'https://images.unsplash.com/photo-1556761175-5973dc0f32e7?w=800',
    ],
    createdAt: daysAgo(21),
  },
  {
    id: 'seed_event_05',
    title: 'Community Gathering',
    subtitle: '@Cultural Meet',
    location: 'Istanbul, Turkey',
    description:
      'An annual cultural gathering celebrating diversity and community spirit in the heart of Istanbul.',
    phone: '+90 212 555 0100',
    email: 'gather@is.tr',
    imageUrls: [
      'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=800',
    ],
    createdAt: daysAgo(35),
  },
  {
    id: 'seed_event_06',
    title: 'Tech Summit',
    subtitle: '@Innovation Forum',
    location: 'Dubai, UAE',
    description:
      'A premier technology summit covering AI, blockchain, and the future of innovation, hosted in the tech hub of Dubai.',
    phone: '+971 4-555-0100',
    email: 'summit@tech.ae',
    imageUrls: [
      'https://images.unsplash.com/photo-1518770660439-4636190af475?w=800',
    ],
    createdAt: daysAgo(1),
  },
];

// ─────────────────────────────────────────────────────────
// Seed / delete
// ─────────────────────────────────────────────────────────
async function seedUsers() {
  const batch = db.batch();
  for (const u of USERS) {
    const { id, ...data } = u;
    batch.set(
      db.collection('users').doc(id),
      {
        ...data,
        fcmTokens: [],
        role: 'user',
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
  await batch.commit();
  console.log(`✓ Seeded ${USERS.length} users`);
}

async function seedEvents() {
  const batch = db.batch();
  for (const e of EVENTS) {
    const { id, ...data } = e;
    batch.set(db.collection('events').doc(id), data, { merge: true });
  }
  await batch.commit();
  console.log(`✓ Seeded ${EVENTS.length} events`);
}

async function deleteSeed() {
  const jobs = [];
  for (const u of USERS) {
    jobs.push(db.collection('users').doc(u.id).delete());
  }
  for (const e of EVENTS) {
    jobs.push(db.collection('events').doc(e.id).delete());
  }
  await Promise.all(jobs);
  console.log(`✓ Removed ${USERS.length + EVENTS.length} seed docs`);
}

async function main() {
  console.log(`Target project: ${projectId || '(from ADC)'}`);
  if (shouldDelete) {
    await deleteSeed();
  } else {
    await seedUsers();
    await seedEvents();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Seed failed:', err);
    process.exit(1);
  });
