# Iter / Coil — Extensible Server-Driven Hono Backend

Turnkey, self-hosted, scalable, and secure backend built with **[Hono](https://hono.dev/)**, **[Drizzle ORM](https://orm.drizzle.team/)**, and **PostgreSQL**. Completely replaces **Firebase** and **Supabase** for database, authentication, real-time presence, and media storage, while utilizing Firebase strictly for **Firebase Cloud Messaging (FCM)** push notifications.

---

## 🌟 Zero-AppStore-Update Architecture

The mobile app no longer requires App Store / Google Play submissions for business logic or UI updates. This backend solves remote updates through:

1. **Server-Driven UI (SDUI)** (`/api/v1/dynamic/screens/:screenId`):
   - Dynamic banner blocks, carousels, announcement modals, and custom tab navigation layouts are served directly as JSON from the server.
   - Deep link action mappings (`action: "navigate", target: "/event/:id"`, `action: "open_url"`).
2. **Remote Feature Flags & Version Gating** (`/api/v1/dynamic/config`):
   - Remotely toggle features (Stories, Reposts, Live Streams, Polls, Direct Messages).
   - Enforce minimum app versions (`minAppVersion`) with force-update dialogs.
   - Toggle maintenance mode with custom messages and platform bypasses.
3. **Dynamic Rules & Content Enums** (`/api/v1/dynamic/enums`):
   - Categories, event types, profile professions, field options, academic levels, and goals are dynamically fetched from the server.
   - Profanity wordlists and moderation regex patterns are delivered dynamically.
4. **Dynamic AI Gateway Orchestration** (`/api/v1/ai/translate`):
   - Multi-provider fallback engine (Gemini, Claude, OpenAI, Azure). The client never hardcodes AI keys.
5. **Flexible Schema Metadata (`metadata` JSONB)**:
   - Entities (`users`, `posts`, `chats`, `events`, `stories`) feature an extensible `metadata` field to store arbitrary attributes without database migrations.

---

## 🏗️ Architecture & Technology Stack

| Component | Technology | Replaces |
|---|---|---|
| **Framework** | [Hono](https://hono.dev/) on Node.js / Bun | Firebase Functions & Supabase Edge |
| **Database** | PostgreSQL 16+ with [Drizzle ORM](https://orm.drizzle.team/) | Cloud Firestore & Realtime DB |
| **Authentication** | JWT Access & Refresh tokens + OAuth validation | Firebase Auth |
| **Media Storage** | Local Disk Storage / S3 / Cloudflare R2 | Supabase Storage & Firebase Storage |
| **Realtime** | Native WebSockets (`/ws`) | Firebase Realtime Database |
| **Push Notifications** | Firebase Admin SDK (`firebase-admin/messaging`) | *Kept as standard mobile push gateway* |
| **Validation** | Zod (`@hono/zod-validator`) | Client-side rules |
| **API Docs** | Interactive OpenAPI / Swagger UI (`/docs`) | Manual documentation |

---

## 🚀 Quick Start

### Option 1: Docker Compose (Recommended)

Starts PostgreSQL and the Hono Backend together:

```bash
docker compose up -d
```

Access the interactive API docs at: [http://localhost:3000/docs](http://localhost:3000/docs)

---

### Option 2: Local Development

#### 1. Install Dependencies
Using **npm** or **Bun**:
```bash
npm install
# or
bun install
```

#### 2. Configure Environment
Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```
Ensure `DATABASE_URL` points to your running PostgreSQL instance.

#### 3. Run Migrations & Seed Initial Data
```bash
# Generate schema SQL
npm run db:generate

# Apply migrations
npm run db:migrate

# Seed default configs, initial admin, dynamic enums, and SDUI screens
npm run db:seed
```

Default seeded superadmin credentials:
- **Email**: `admin@iter.app`
- **Password**: `Admin@123456`

#### 4. Start Development Server
```bash
npm run dev
# or
bun run dev
```

Server runs on: [http://localhost:3000](http://localhost:3000)  
Interactive Swagger docs: [http://localhost:3000/docs](http://localhost:3000/docs)

---

## 📡 Flutter App Client Integration

### 1. Base URL & Endpoints
Set `API_BASE_URL=http://<your-server-ip>:3000/api/v1` in your mobile `.env`.

### 2. Service Replacement Matrix

| Flutter Service | Old Provider | New Endpoint |
|---|---|---|
| `AuthService` | Firebase Auth | `/api/v1/auth/signup`, `/login`, `/google`, `/apple` |
| `PostService` | Firestore `posts` | `/api/v1/posts`, `/api/v1/posts/qa` |
| `CommentService` | Firestore `comments` | `/api/v1/comments/post/:postId` |
| `StoryService` | Firestore `stories` | `/api/v1/stories`, `/api/v1/stories/active` |
| `ChatService` | Firestore `chats` | `/api/v1/chats/conversations`, `/messages` |
| `PresenceService` | Realtime DB `presence` | WebSocket `/ws` (`type: "heartbeat"`) |
| `TypingService` | Realtime DB `typing` | WebSocket `/ws` (`type: "typing"`) |
| `StorageService` | Supabase Edge `issue-upload-url` | `POST /api/v1/storage/upload-url` |
| `AdminService` | Firestore `adminConfig` | `GET /api/v1/dynamic/config`, `/admin/config` |
| `TranslateService`| Firebase Callable `translateText` | `POST /api/v1/ai/translate` |
| `FcmService` | Client token save | `POST /api/v1/notifications/fcm-token` |

---

## 🔔 Firebase Cloud Messaging (FCM) Setup

To deliver native push notifications on iOS and Android:
1. Go to Firebase Console -> **Project Settings** -> **Service Accounts**.
2. Click **Generate new private key** (downloads a `.json` file).
3. Set in `.env`:
   ```env
   FIREBASE_SERVICE_ACCOUNT_KEY=/path/to/serviceAccountKey.json
   ```
   *Note: If unset, the backend runs in mock log mode and will not crash.*

---

## 🧪 Testing

Run the automated API test suite:
```bash
npm run test
```
