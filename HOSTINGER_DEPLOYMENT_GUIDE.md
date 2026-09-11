# 🚀 Hostinger Deployment & Domain Migration Guide

This guide explains how to deploy the **Iter (Coil)** Hono backend and MySQL database to **Hostinger**, and how to switch all URLs (database records, backend endpoints, and Flutter app) with **a single command**.

---

## 🌟 The Central Configuration File: `ecosystem.config.json`

Both your local environment and Hostinger production environment are centrally managed in:
👉 [`ecosystem.config.json`](file:///g:/msi/github/Iter/ecosystem.config.json)

```json
{
  "activeProfile": "local",
  "profiles": {
    "local": {
      "name": "Local Development (PC + Android Phone via Wi-Fi)",
      "appUrl": "http://192.168.1.194:3000",
      "storagePublicUrl": "http://192.168.1.194:3000/uploads",
      "databaseUrl": "mysql://root:1842@localhost:3306/iter_db",
      "flutterApiBaseUrl": "http://192.168.1.194:3000/api/v1"
    },
    "hostinger": {
      "name": "Hostinger Production Server",
      "appUrl": "https://api.yourdomain.com",
      "storagePublicUrl": "https://api.yourdomain.com/uploads",
      "databaseUrl": "mysql://u123456789_iter:YOUR_DB_PASSWORD@localhost:3306/u123456789_iter_db",
      "flutterApiBaseUrl": "https://api.yourdomain.com/api/v1"
    }
  }
}
```

---

## ⚡ How to Switch Everything in 1 Command

When you buy Hostinger and set up your domain (e.g. `https://api.yourdomain.com`):

### Option A: Using the Hostinger Profile in `ecosystem.config.json`
1. Open [`ecosystem.config.json`](file:///g:/msi/github/Iter/ecosystem.config.json).
2. Put your real Hostinger domain and database password under `"hostinger"`.
3. Run:
   ```bash
   cd backend-hono
   npm run switch-env hostinger
   ```

### Option B: Quick Domain Switch via Command Line
Run this one command directly with your domain:
```bash
cd backend-hono
npm run switch-domain https://api.yourdomain.com
```

### What happens automatically when you run this command:
1. **Flutter App Updated**: Updates `API_BASE_URL=https://api.yourdomain.com/api/v1` in Flutter's [`.env`](file:///g:/msi/github/Iter/.env).
2. **Backend Config Updated**: Updates `APP_URL` and `STORAGE_PUBLIC_URL=https://api.yourdomain.com/uploads` in [`backend-hono/.env`](file:///g:/msi/github/Iter/backend-hono/.env).
3. **All MySQL Database Records Replaced**:
   - Automatically connects to MySQL.
   - Converts all old local IP links (`http://192.168.1.194:3000/uploads/...`) ➡️ `https://api.yourdomain.com/uploads/...`
   - Converts any remaining Supabase links (`https://htiwlasyspclmsyslaco.supabase.co/storage/v1/object/public/...`) ➡️ `https://api.yourdomain.com/uploads/...`
   - Scans and updates:
     - `users` (avatar and cover URLs)
     - `posts` (image arrays, video arrays, author avatar)
     - `comments` (author avatar)
     - `events` (cover image URLs)
     - `stories` (image URLs, video URLs, author avatar)
     - `messages` (chat photos, videos, and voice notes)

### If you want to switch back to local PC development:
```bash
npm run switch-env local
```
Everything immediately reverts back to your local PC Wi-Fi IP.

---

## 📋 Step-by-Step Hostinger Deployment Walkthrough

### Step 1: Create MySQL Database on Hostinger
1. Log in to Hostinger **hPanel**.
2. Navigate to **Databases** ➡️ **MySQL Databases**.
3. Create a new database:
   - **Database Name**: e.g. `u123456789_iter_db`
   - **Username**: e.g. `u123456789_iter`
   - **Password**: (create a secure password, e.g. `StrongPass123!`)
4. Note down the full database name and user (Hostinger prefixes them with your account ID, e.g. `u123456789_`).

### Step 2: Set up Node.js on Hostinger
- **If using Hostinger VPS (Recommended)**:
  - Connect via SSH.
  - Install Node.js 20+ (`nvm install 20`).
  - Clone/upload your `backend-hono` folder.
  - Install dependencies: `npm install`.
  - Start with PM2: `pm2 start "npm run dev" --name "iter-backend"` (or run via Node).
- **If using Hostinger Cloud / Web Hosting with Node.js**:
  - In hPanel, go to **Advanced** ➡️ **Node.js**.
  - Click **Create Application**.
  - Node.js version: **20.x** (or higher).
  - Application root: `/backend-hono` (or your chosen directory).
  - Application startup file: `dist/index.js` or `src/index.ts`.
  - Application URL: e.g. `https://api.yourdomain.com`.

### Step 3: Run Database Migrations on Hostinger
Once connected to the Hostinger database:
```bash
npm run db:migrate
npm run db:seed
```
This generates all 38 tables, Dynamic UI schemas, initial admin, and configs.

### Step 4: Transfer Uploaded Media Files
Copy your local uploads folder:
👉 [`backend-hono/uploads/`](file:///g:/msi/github/Iter/backend-hono/uploads/)
To the Hostinger backend directory at `/backend-hono/uploads/` via SFTP or Hostinger File Manager.

### Step 5: Import Firebase Data (if not done locally)
If importing directly into Hostinger:
1. Place your `serviceAccountKey.json` into `backend-hono/`.
2. Run:
   ```bash
   npm run db:import-firebase
   ```
   All users, posts, comments, chats, events, and stories are imported, and all media URLs automatically point to your Hostinger domain.

### Step 6: Build or Run the Flutter Mobile App
Since `API_BASE_URL` in [`.env`](file:///g:/msi/github/Iter/.env) was already updated by `npm run switch-env hostinger`, simply run:
```bash
flutter build apk --release
```
Your Flutter app is now communicating with Hostinger in production!
