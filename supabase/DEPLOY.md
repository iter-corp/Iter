# Supabase setup for COIL

This folder contains:
- `functions/issue-upload-url/index.ts` — Edge function that verifies Firebase ID tokens and issues signed Supabase Storage upload URLs.
- `rls_policies.sql` — Row-level security policies for the `avatars` and `posts` buckets.

Follow these steps **once** to get uploads working. No Supabase CLI install needed — everything is done through the dashboard.

---

## 1. Apply storage RLS policies

1. Go to Supabase Dashboard → **SQL Editor** → **New query**.
2. Open `rls_policies.sql` from this folder, copy the contents, paste into the editor.
3. Click **Run**.
4. Verify under Storage → `avatars` bucket → Policies that 2 policies now exist (public read + service write).
5. Same check for `posts` bucket.

---

## 2. Create the Edge Function in the dashboard

1. Go to Supabase Dashboard → **Edge Functions** (lightning-bolt icon) → **Create a new function**.
2. Name it exactly: `issue-upload-url`.
3. In the code editor, **delete the default template** and paste the full contents of `functions/issue-upload-url/index.ts`.
4. Click **Deploy function**.

---

## 3. Set the required secrets

The edge function needs to know your Firebase project ID. The service role key and Supabase URL are **automatically available** inside the edge function runtime — you only need to add Firebase project ID.

1. Go to Edge Functions → **Secrets** (or Project Settings → Edge Functions → Secrets).
2. Click **Add secret**.
3. Name: `FIREBASE_PROJECT_ID`
4. Value: `coil-50528`
5. Save.

---

## 4. Verify

From your machine (with `curl` or PowerShell), invoke the function without a token — it should respond with `401 missing bearer token`:

```bash
curl -X POST https://htiwlasyspclmsyslaco.supabase.co/functions/v1/issue-upload-url \
  -H "Content-Type: application/json" \
  -H "apikey: YOUR_ANON_KEY" \
  -d '{"bucket":"avatars","kind":"avatar","ext":"jpg"}'
```

Expected response:
```json
{"error":"missing bearer token"}
```

If you get that, it's deployed and working. The Flutter app will call it with a real Firebase ID token.

---

## Redeploying later

If you edit `functions/issue-upload-url/index.ts`, just paste the new code into the dashboard editor and click **Deploy function** again. No CLI required.

When you're ready to switch to CLI workflow later:
```bash
npm install -g supabase
supabase login
supabase link --project-ref htiwlasyspclmsyslaco
supabase functions deploy issue-upload-url
```
