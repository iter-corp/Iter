# PowerPoint Generation Prompt — Iter Graduation Defense

This file contains a single, complete, paste-ready prompt for **Claude.ai**, **Microsoft Copilot in PowerPoint**, or **ChatGPT with a slide-maker tool** that will generate a polished `.pptx` deck for the **Iter** graduation defense.

The prompt below is exhaustively specific about typography, color, spacing, alignment, slide masters, and speaker notes. The output should be defense-ready with minimal manual tweaking — only the screenshot/diagram placeholders need to be filled in by hand.

## How to use it

1. Open **https://claude.ai** (or **Microsoft Copilot inside PowerPoint** → Designer → "Create from a prompt").
2. Copy **everything between the two `═════` lines below** — start at "**You are a senior presentation designer**…" and stop at "**End of prompt.**".
3. Paste it as a single message.
4. Download the resulting `.pptx`.
5. Open in PowerPoint and replace the placeholder strings (`{{SCREENSHOT: home_screen}}`, `{{DIAGRAM: feed_architecture}}`, etc.) with actual images from the running app.
6. Run through the deck once in Presenter View to verify speaker notes are visible.

═══════════════════════════════════════════════════════════════════════════

You are a senior presentation designer producing a **graduation-defense-grade PowerPoint deck** for a university computer-science capstone project. The project is **Iter — A Collaborative Opportunity Discovery and Student Engagement Platform**. Five team members will present 17 slides in 20 minutes.

Produce a **single `.pptx` file** in **16:9 widescreen (13.333 in × 7.5 in / 1920 × 1080 px)** with the exact specifications below. Treat every value as a hard constraint, not a suggestion. Where the prompt says "exactly 32 pt", do not output 30 or 34.

# 0. GLOBAL DESIGN SYSTEM

## 0.1 Color palette (use these hex values verbatim)

| Token | Hex | Role |
|---|---|---|
| `--primary` | `#7C3AED` | Brand primary (deep violet — academic, trustworthy) |
| `--primary-light` | `#A78BFA` | Hover/accent gradient end |
| `--primary-dark` | `#5B21B6` | Title-slide background, section dividers |
| `--surface` | `#FFFFFF` | Default slide background |
| `--surface-alt` | `#F8FAFC` | Card backgrounds, code blocks |
| `--ink-900` | `#0F172A` | Primary body text, headings |
| `--ink-700` | `#334155` | Secondary body text |
| `--ink-500` | `#64748B` | Captions, footer, metadata |
| `--ink-300` | `#CBD5E1` | Hairline dividers, table borders |
| `--success` | `#10B981` | "✓ secure", positive indicators |
| `--warning` | `#F59E0B` | Caution callouts |
| `--danger` | `#EF4444` | "❌ avoided patterns" |
| `--code-bg` | `#0F172A` | Code-snippet background |
| `--code-fg` | `#E2E8F0` | Code-snippet foreground |

**Never use** pure red `#FF0000`, pure blue `#0000FF`, clip-art colors, or any saturated yellow other than `#F59E0B`. **No emojis on slides** unless the brief explicitly lists one for a specific slide (slide 15 only).

## 0.2 Typography

Embed and use these fonts. If unavailable, fall back to the listed system equivalent.

| Role | Family | Fallback | Weight | Size | Letter-spacing | Line-height |
|---|---|---|---|---|---|---|
| Slide title | **Inter** | Segoe UI | **700 Bold** | **40 pt** | -0.5 px | 1.15 |
| Slide subtitle | Inter | Segoe UI | 500 Medium | 22 pt | 0 | 1.3 |
| Section header (inside slide) | Inter | Segoe UI | 600 Semibold | 24 pt | 0 | 1.25 |
| Body bullets | Inter | Segoe UI | 400 Regular | 18 pt | 0 | 1.5 |
| Body emphasis | Inter | Segoe UI | 600 Semibold | 18 pt | 0 | 1.5 |
| Table header cell | Inter | Segoe UI | 600 Semibold | 14 pt | 0.5 px (uppercase) | 1.3 |
| Table body cell | Inter | Segoe UI | 400 Regular | 14 pt | 0 | 1.35 |
| Caption / footer | Inter | Segoe UI | 400 Regular | 11 pt | 0.2 px | 1.4 |
| Slide number | Inter | Segoe UI | 500 Medium | 10 pt | 0.5 px | 1 |
| Code / monospace | **JetBrains Mono** | Consolas | 400 Regular | 13 pt | 0 | 1.5 |

- All body text is `--ink-900`. Captions are `--ink-500`.
- Title-slide / section-divider titles are **white (`#FFFFFF`)**.
- **Never set text in ALL CAPS** except table headers and the slide-number footer.
- **No italic** for emphasis — use 600 weight.

## 0.3 Spacing & grid

- **Outer margins:** 0.6 in (≈ 86 px) on left, right, and top. Footer band starts at 7.0 in (bottom 0.5 in reserved).
- **12-column grid** with 24 px gutters across the content area.
- **Title top padding:** 0.6 in from top.
- **Title bottom padding:** 0.4 in to next element.
- **Bullet line spacing:** 12 pt before, 0 pt after; line-height 1.5.
- **Section break between blocks of content:** 0.35 in.
- **Card corner radius:** 12 pt. Code-block corner radius: 8 pt. Pill corner radius: 999 pt (full round).
- **Default card padding:** 16 pt all sides.
- **Default shadow:** `0 4px 12px rgba(15, 23, 42, 0.08)` for cards on light backgrounds. No shadow on flat sections.

## 0.4 Master slide layout

Every slide (except 1, 15, 17 which are full-bleed) follows this master:

- **Top-left:** Slide title (40 pt bold, `--ink-900`).
- **Below the title:** A 4 px tall, 64 px wide bar in `--primary` (`#7C3AED`) at 0.6 in from the left edge — visual accent under every title.
- **Bottom-left footer:** Word **"Iter"** in 11 pt 500 weight, `--ink-500`, at 0.6 in from left, 7.15 in from top.
- **Bottom-center footer:** A 1 px hairline divider in `--ink-300` spanning from 0.6 in to 12.7 in horizontally, at 7.0 in from top.
- **Bottom-right footer:** Slide number in 10 pt 500 weight, `--ink-500`, format `08 / 17`, right-aligned at 12.7 in from left, 7.15 in from top.

## 0.5 Speaker notes

Every slide MUST have a 60–120-word **speaker-notes block** in the PowerPoint notes pane (View → Notes Page). The notes are written in **conversational English**, not bullet style — they are the verbatim script for the presenter. Use the speaker-notes text I provide for each slide below, exactly as written.

# 1. SLIDE MASTERS

Define and apply two master layouts:

## Master A — "Full-bleed Brand" (used by slides 1, 15, 17)

- Background: **linear gradient** from `--primary-dark` (`#5B21B6`) at top-left to `--primary` (`#7C3AED`) at bottom-right, angle 135°.
- All text in `#FFFFFF`.
- No footer hairline, no slide number visible (but keep them in the file for consistency in print).
- A subtle decorative element: in the top-right corner, render a 280 px × 280 px circle outline at 20% white opacity, stroke 2 px, with its center at (12.5 in, -0.3 in) so half is off-canvas. Add a second similar circle at (0.4 in, 7.0 in), 200 px diameter, 15% opacity, half off-canvas bottom-left. These create a quiet sense of motion without imagery.

## Master B — "Content" (used by all other slides, 2–14 and 16)

- Background: `--surface` (`#FFFFFF`) flat.
- Master layout per §0.4.

# 2. SLIDE-BY-SLIDE SPECIFICATION

For each slide, the heading shows: **Slide # — Title (presenter) [master]**.

Layout instructions are precise. Render exactly as described.

---

## Slide 1 — Title (Honya) [Master A]

**Layout:** Centered column, vertical alignment middle.

- At top-center, render a **logo placeholder**: a 96 px × 96 px rounded-square (radius 24 pt) filled with `#FFFFFF` at 12% opacity, containing the letter **"i"** in Inter 600 Semibold, 56 pt, color `#FFFFFF`. Center at (6.67 in, 1.6 in).
- Below the logo, 0.5 in gap, a wordmark **"Iter"** in Inter **800 ExtraBold, 96 pt**, color `#FFFFFF`, letter-spacing -2 px, centered horizontally.
- Below the wordmark, 0.2 in gap, the tagline **"A Collaborative Opportunity Discovery and Student Engagement Platform"** in Inter 400 Regular, 22 pt, color `#FFFFFF` at 85% opacity, centered, max width 10 in.
- 0.6 in below the tagline, a single horizontal hairline 1 px tall, 80 px wide, color `#FFFFFF` at 40% opacity.
- 0.4 in below that, the line **"Graduation Defense · 2026"** in Inter 500 Medium, 16 pt, `#FFFFFF` at 70% opacity, centered.
- At the bottom, 6.5 in from top, the team line **"Honya  ·  Naz  ·  Zanyar  ·  Mohammed  ·  Kaziwa"** in Inter 500 Medium, 14 pt, `#FFFFFF` at 90% opacity, centered, with figure-spaces between names.

**Speaker notes:**
> "Good [morning / afternoon]. We're presenting Iter, a Collaborative Opportunity Discovery and Student Engagement Platform. I'm Honya, and with me are Naz, Zanyar, Mohammed, and Kaziwa. Iter is a full-stack mobile application built with Flutter, Firebase Cloud Functions, Cloud Firestore, Supabase storage, and Agora live audio/video. Over the next twenty minutes, we'll show you the problem we set out to solve, how the app is architected, how every piece fits together, and we'll end with a live demo on a real phone."

---

## Slide 2 — Problem & Mission (Honya) [Master B]

**Title:** "The Fragmentation of Opportunity"
**Layout:** Two-column 50/50, split at 6.4 in horizontally. Each column has a colored heading bar at top.

**LEFT COLUMN — "The Problem"**
- Header: a pill background `--danger` `#EF4444` at 12% opacity, height 36 pt, width fits content, corner radius 999. Inside: **"❌ THE PROBLEM"** in Inter 600 Semibold, 12 pt, color `--danger`, letter-spacing 1 px, all caps. Padding 6 pt vertical, 14 pt horizontal.
- 0.25 in below, three bullets in 18 pt body, `--ink-700`. Each bullet starts with a 16×16 px outlined dot in `--ink-300`, then 8 pt gap, then text:
  1. Scholarships, internships, research, and conferences are scattered across **dozens** of platforms.
  2. Discovery today depends on **proximity, privilege, or chance** — not merit or fit.
  3. Generic professional networks ignore academic context and underserved languages.

**RIGHT COLUMN — "Our Solution"**
- Header: pill background `--primary` `#7C3AED` at 10% opacity, height 36 pt, corner radius 999. Inside: **"✓ ITER"** in Inter 600 Semibold, 12 pt, color `--primary`, letter-spacing 1 px, all caps.
- 0.25 in below, three bullets in 18 pt body, `--ink-700`. Bullet markers are filled 8×8 px squares in `--primary`:
  1. A **profile-driven personalization engine** filters opportunities by role, field, level, and goals.
  2. A **social platform** for milestones, discussion, peer connection, and translation.
  3. A **verified-partner governance model** — only vetted organizations publish events.

**BOTTOM STRIP** (full width, 0.4 in from bottom of content area)
A horizontal row of 4 small cards. Each card: 2.4 in wide × 1.1 in tall, corner radius 12, background `--surface-alt`, padding 16 pt. Each card contains:
- A 24 px line-icon in `--primary` (use Lucide-style outlined icons): **layout-grid** (Feed), **calendar-check** (Events), **message-circle** (Messaging), **video** (Live).
- Below icon, 8 pt gap, label in Inter 600 Semibold, 14 pt, `--ink-900`: "Feed", "Events", "Messaging", "Live".

**Speaker notes:**
> "In an increasingly interconnected academic landscape, students and researchers face one persistent and largely unaddressed challenge — the fragmentation of opportunity. Scholarships, internships, research programs, doctoral calls, and academic conferences are scattered across dozens of platforms and informal networks. Discovery today depends on proximity, privilege, or chance, not on merit or fit. Iter was conceived as a direct response. Its mission is to be a unified, student-native ecosystem where opportunity discovery is not passive but intelligent and tailored, surrounded by a warm social platform and protected by a verified-partner governance model. Every student, regardless of background or geography, deserves an equal right to find what could define their career."

---

## Slide 3 — User Journey (Naz) [Master B]

**Title:** "From Sign-Up to Personalized Discovery"

**Layout:** Horizontal step-flow ribbon centered vertically.

- 7 numbered circular nodes connected by 2-px lines in `--ink-300`. Each node is 56 px diameter, filled `--primary`, with white centered number (Inter 700 Bold, 18 pt). Spacing: nodes evenly spread across 11.4 in.
- Below each node, 0.2 in gap, a label in Inter 600 Semibold, 13 pt, `--ink-900`, centered, max 2 lines:
  1. "Splash"
  2. "Sign Up"
  3. "Academic Profile"
  4. "Personalized Feed"
  5. "Events & Forum"
  6. "Chat / Live"
  7. "Travel Mode"
- Below the labels, 0.4 in gap, three phone-frame placeholders side-by-side, each 1.7 in wide × 3.6 in tall, corner radius 24 pt, with placeholder text inside (background `--ink-300` at 20% opacity, centered text in `--ink-500`, 12 pt):
  - `{{SCREENSHOT: signup_screen}}`
  - `{{SCREENSHOT: onboarding_screen}}`
  - `{{SCREENSHOT: home_screen}}`
- Center the three phones horizontally as a group.

**Speaker notes:**
> "A new user's path through Iter is intentionally short, then highly personalized. They land on a splash screen while Firebase initialises. They sign up with email, Google, or Apple. They then complete onboarding by selecting their profession — student, researcher, professor, or traveler — their field of study, their academic level, and their goals. The router blocks them from the home feed until that profile is complete, so we never have anonymous browsing. From there, the personalized events surface, the social feed, the discussion forum, messaging, live rooms, and a travel mode that surfaces opportunities near their GPS location. Admins and approved organizations have a separate dashboard."

---

## Slide 4 — Frontend Architecture (Naz) [Master B]

**Title:** "Built on Flutter, Riverpod, and go_router"

**Layout:** Two-column, 60/40. Left column = layered diagram. Right column = tech panel.

**LEFT — Layered diagram** (vertical stack of 4 rounded rectangles, each full width of column, 0.5 in tall, 8 pt gap between):

| Layer | Fill | Label |
|---|---|---|
| Top (UI) | `--primary` at 8% opacity, 1 px stroke `--primary` | "Material Widgets · 31 screens · 18 reusable widgets" |
| 2nd | `--primary-light` at 15% opacity | "Riverpod · 18 state providers" |
| 3rd | `--ink-300` at 30% opacity | "go_router · auth-aware redirects" |
| Bottom | `--ink-500` at 15% opacity | "Services layer · 22 services" |

Each label: Inter 600 Semibold, 15 pt, `--ink-900`, vertically centered, 16 pt left padding.

**RIGHT — Tech panel**
- Header: "Tech Stack" in Inter 600 Semibold, 16 pt, `--ink-500`, letter-spacing 0.5 px, all caps.
- 8 pt below: a vertical list of 7 items, each on its own line, 16 pt body Inter 400 Regular. Format: a 6×6 px bullet square in `--primary` + 8 pt gap + label:
  1. **Flutter** — Android · iOS · Web
  2. **Dart** language
  3. **Riverpod** state management
  4. **go_router** navigation
  5. Material Design + dark/light theme
  6. **3 languages:** EN · AR · CKB (custom Kurdish delegate)
  7. **Responsive** layout for phones · tablets · web

**Speaker notes:**
> "Under the hood we used Flutter with Dart — one codebase for Android, iOS, and web. State management is handled by Riverpod across eighteen providers covering auth, posts, chats, follows, reactions, and notifications. Navigation is declarative with go-router, using auth-aware redirects so unauthenticated users never reach protected screens, and users who haven't finished onboarding cannot reach the home feed. We support three languages including Kurdish Sorani, which required us to write a custom Material localization delegate because Flutter doesn't ship one. Images and videos cache locally, and the responsive bootstrap widget scales paddings and fonts across screen sizes."

---

## Slide 5 — Database Overview (Zanyar) [Master B]

**Title:** "Three Stores, One Source of Truth"

**Layout:** Three columns of equal width (≈ 3.9 in each), with header bars on top of each column.

**Column 1 — "Cloud Firestore (primary)"**
- Header bar: full column width, height 32 pt, fill `--primary`, white text Inter 600 Semibold 14 pt, centered: "CLOUD FIRESTORE".
- Below, a card (corner radius 12, `--surface-alt`, padding 16 pt) listing top-level collections. Each line in Inter 500 Medium 13 pt, monospace family for collection names, `--ink-900`. 6 pt line spacing.
  - `users/{uid}`
  - `posts/{postId}`
  - `stories/{storyId}`
  - `chats/{chatId}`
  - `events/{eventId}`
  - `eventChats/{eventId}`
  - `feeds/{uid}/timeline`
  - `notifications/{uid}/items`
  - `eventRegistrations`
  - `contactRequests`
  - `postReports` · `userReports` · `discussReports` · `errorReports`
  - `blacklist`
  - `adminConfig`

**Column 2 — "Realtime DB"**
- Header bar same style, fill `--primary-light`, text white: "REALTIME DB".
- Card lists:
  - `presence/{uid}` — online / offline
  - `typing/{chatId}/{uid}` — typing indicator
- A 0.2 in gap, then a caption in Inter 400 Regular, 12 pt, `--ink-500`: "Used only where millisecond latency matters and queries aren't needed."

**Column 3 — "Supabase Storage"**
- Header bar same, fill `#10B981` (green), text white: "SUPABASE STORAGE".
- Card lists:
  - `avatars/`
  - `posts/`
  - `stories/`
  - `events/`
- Caption below: "Public read · service-role writes via signed URLs."

**Speaker notes:**
> "Iter uses three stores in concert. Cloud Firestore is our primary NoSQL document database — fifteen top-level collections covering users, posts, stories, chats, events, the per-user pre-computed feed, notifications, registrations, support threads, four moderation queues, the blacklist, and admin configuration. Firebase Realtime Database is used only for live presence and typing indicators where millisecond latency matters. Supabase Storage holds large media — avatars, post images, post videos, story media — uploaded directly by the client through signed URLs, which keeps Firebase egress cost down."

---

## Slide 6 — Security Rules (Zanyar) [Master B]

**Title:** "Server-Enforced Access Control"

**Layout:** Two columns, 55/45. Left column = code snippet card. Right column = bullet list of defensive patterns.

**LEFT — Code card**
- Card: corner radius 8, fill `--code-bg` (`#0F172A`), padding 18 pt.
- Inside, monospace JetBrains Mono 12 pt, `--code-fg` (`#E2E8F0`), with simple syntax color hints: keywords (`match`, `allow`, `if`) in `#A78BFA`, string literals in `#10B981`, comments in `--ink-500`.
- Content (exactly):
  ```firestore
  match /posts/{postId} {
    allow read: if signedIn();
    allow create: if signedIn() &&
      request.resource.data.authorUid == request.auth.uid;
    allow update: if signedIn() && (
      resource.data.authorUid == request.auth.uid ||
      isAdmin() ||
      request.resource.data.diff(resource.data)
        .affectedKeys()
        .hasOnly(['commentsCount', 'likesCount'])
    );
  }

  // Default deny — block anything not whitelisted
  match /{document=**} {
    allow read, write: if false;
  }
  ```

**RIGHT — Defensive patterns** (header + 5 bullets)
- Header: "Defensive Patterns" in Inter 600 Semibold, 18 pt, `--ink-900`.
- 5 bullets, 16 pt body, `--ink-700`, marker = 6×6 filled square in `--primary`, 10 pt gap between bullets:
  1. Role helpers: `signedIn` · `isSelf` · `isAdmin` · `isOrgAdmin` · `isChatParticipant`.
  2. Document-shape validation (`hasOnly`, size limits, type checks).
  3. `feeds/{uid}/timeline/` write-blocked for **every** client.
  4. Counters writable only by Cloud Functions, never by clients.
  5. Final default-deny block stops anything not whitelisted.

**Speaker notes:**
> "The most important defensive code in Iter is in firestore.rules — six hundred and forty-six lines of declarative access policy that runs server-side on every read and write. Clients cannot bypass it. We use helper functions for role checks, validate document shapes with hasOnly and size limits, write-block the feeds collection so only Cloud Functions can populate it, and restrict counter updates to Cloud Functions so users cannot inflate their stats. The final default-deny block at the bottom blocks anything we didn't explicitly allow — a fail-closed posture by design."

---

## Slide 7 — Supabase RLS & Signed Uploads (Zanyar) [Master B]

**Title:** "Two-Stack Storage with Token-Verified Uploads"

**Layout:** Horizontal sequence diagram occupies the top 60% of the slide, an RLS summary card at the bottom 40%.

**TOP — Sequence diagram**
- Three vertical lifelines, evenly spaced at 2.5 in, 6.67 in, 10.83 in from the left:
  - **Client (Flutter)** — label at top, 14 pt Inter 600, `--ink-900`.
  - **Supabase Edge Function** — label.
  - **Supabase Storage** — label.
- Each lifeline is a 1 px dashed line in `--ink-300` from y=1.6 in to y=4.6 in. Above each lifeline a 48×48 px circle in `--surface-alt`, 1 px stroke `--primary`, with a small icon: smartphone, server, cloud.
- 5 horizontal arrows (Inter 500 Medium 12 pt labels above each arrow, `--ink-700`):
  1. From Client → Edge Function at y=2.1 in: "1. POST /issue-upload-url (Firebase ID token)"
  2. Edge Function self-arrow (semi-circle) at y=2.6 in: "2. Verify token · check blacklist · sign URL"
  3. Edge Function → Client at y=3.1 in: "3. { signedUrl, publicUrl }"
  4. Client → Storage at y=3.6 in: "4. PUT bytes"
  5. Storage → Client at y=4.1 in: "5. 201 Created"

**BOTTOM — RLS card**
- A horizontal pill card spanning the content area: corner radius 12, fill `--surface-alt`, padding 16 pt, 1 px stroke `--ink-300`.
- Inside, two columns 50/50:
  - LEFT: **"RLS Policy"** in 16 pt 600 Semibold `--ink-900`, then two lines 14 pt 400 Regular `--ink-700`: "Public READ on all buckets — same as a CDN.", "WRITE allowed only via service-role (server-side key)."
  - RIGHT: a green pill `--success` 12% opacity, 32 pt height, containing in 13 pt 600 Semibold `--success`: "✓ Anon key alone cannot upload — needs a Firebase-verified signed URL."

**Speaker notes:**
> "Large media goes to Supabase Storage instead of Firebase Storage because Firebase egress gets expensive at scale. Our security pattern: the client calls our Supabase Edge Function with the Firebase ID token. The Edge Function verifies the token, checks the user isn't blacklisted, generates a unique object key, and signs a one-time upload URL using the Supabase service-role key. The client then uploads bytes directly. Even if an attacker steals our Supabase anon key from a decompiled APK, they still can't upload — they don't have a valid Firebase ID token to exchange for a signed URL."

---

## Slide 8 — Cloud Functions Overview (Mohammed) [Master B]

**Title:** "Ten Modules. Server-Authoritative."

**Layout:** Single full-width data table.

- Table width = full content width (≈ 12.1 in). Two columns: **Module** (35%) and **Responsibility** (65%).
- Header row: height 40 pt, fill `--ink-900`, text `#FFFFFF`, Inter 600 Semibold 13 pt, letter-spacing 0.5 px, all caps, left-padded 14 pt. Column headers: "MODULE" · "RESPONSIBILITY".
- Data rows: height 36 pt, alternating fills `#FFFFFF` and `--surface-alt`. 1 px bottom border `--ink-300`. Inter 400 Regular 14 pt, `--ink-900` for module name (in monospace), `--ink-700` for description, left-padded 14 pt.

| Module | Responsibility |
|---|---|
| `posts.ts` | Fan-out social timeline on post creation |
| `likes.ts` | Notify post author on new like |
| `follows.ts` | Update follower / following counters + notifications |
| `comments.ts` | Comment notifications + counter bumps |
| `messages.ts` | Chat last-message preview + unread increment |
| `notifications.ts` | FCM push fan-out for all notification types |
| `events.ts` | New-event fan-out by country / type preference |
| `live.ts` | Issues Agora RTC tokens (callable) |
| `translate.ts` | Google Gemini translation proxy (callable) |
| `adminUsers.ts` | Admin user-management endpoints (callable) |

- Below table, 0.3 in gap, a single-line footnote in 12 pt Inter 400 Regular `--ink-500`: "TypeScript · Node 20 · firebase-admin · firebase-functions v2 · 100% type-checked at build time"

**Speaker notes:**
> "Our backend is ten Cloud Functions modules, all written in TypeScript on Node 20. They split into two categories — Firestore triggers that fire automatically when documents change, and callable functions invoked directly from the client. Everything runs server-side with the admin SDK, so security rules don't apply to functions, but they do apply to clients. This is the core of our security model: counters and side-effects only happen via Cloud Functions, never via direct client writes — so users cannot fabricate likes, inflate follower counts, or skip moderation."

---

## Slide 9 — The Personalization Algorithm (Mohammed) [Master B]

**Title:** "Profile-Driven Event Relevance Scoring"
**Subtitle (in 22 pt Inter 500, `--ink-700`, directly below title bar):** "`_eventRelevanceScore` — frontend/lib/src/features/screens/event_screen.dart : 62-97"

**Layout:** Two-column 45/55. Left = scoring table. Right = visual ranking demo.

**LEFT — Scoring table**
- Table 5 in wide. Two columns: "Signal" 60%, "Weight" 40%.
- Header row: 36 pt height, fill `--primary`, white text Inter 600 Semibold 13 pt all caps, padding 14 pt. Columns: "SIGNAL" · "WEIGHT".
- Data rows: 40 pt height, alternating `#FFFFFF` / `--surface-alt`, Inter 14 pt:

| Signal | Weight |
|---|---|
| Event text contains user's **field of study** | **+3** |
| Each user **goal** matched in event text | **+2 per goal** |
| User goal matches event **type** | **+2** |
| User **city** equals event city | **+2** |
| Event within **100 km** of user's GPS | **+1** |

- Weight column rendered in Inter 700 Bold 16 pt, color `--primary`, right-aligned, 14 pt padding.
- 0.2 in below the table, a caption in 12 pt Inter 400 Regular, `--ink-500`: "Deterministic · client-side · privacy-preserving (profile never leaves device for scoring)."

**RIGHT — Ranking demo**
- Header: "Example: CS Undergraduate with goals = [Internships, Hackathons]" in 14 pt 600 Semibold, `--ink-700`.
- 0.2 in below, a vertical stack of 4 event cards (full column width). Each card: corner radius 12, padding 14 pt, 1 px stroke `--ink-300`, 0.15 in vertical gap between cards. Inside each card: title in 14 pt 600 Semibold `--ink-900`, type in 12 pt 400 `--ink-500`, score pill on right in `--primary` at 12% opacity, corner-radius 999, padding 4 pt × 10 pt, text in 12 pt 700 Bold `--primary`:
  1. "Google Summer of Code 2026" — Internship · `+7` (Tech +3 · Internship goal +2 · type-match +2)
  2. "ACM ICPC Regional Hackathon" — Hackathon · `+5` (matches Hackathons goal +2 · type-match +2 · city +2 ... [example])
  3. "Medical Ethics Symposium" — Conference · `+0`
  4. "Local Photography Meetup" — Community · `+0`

**Speaker notes:**
> "Iter's central claim is that opportunity discovery should be intelligent and tailored, not chronological. Here is the algorithm that delivers on that. When the user opens the events tab, every event is scored against their academic profile. Field of study match adds three points — it filters out wrong-domain content most aggressively. Each goal matched in the event text adds two points. Goal-to-event-type affinity adds two. City match adds two. Proximity within one hundred kilometers adds one. The list is then sorted by score. The algorithm is deterministic, runs client-side so the profile never leaves the device, and is rule-based on purpose — students should understand why they see what they see. No black-box ML."

---

## Slide 10 — Social Feed: Fan-Out-on-Write (Mohammed) [Master B]

**Title:** "Cheap Reads via Pre-Computed Timelines"

**Layout:** Two diagrams side-by-side at top (50/50), code snippet at bottom.

**LEFT diagram — "Fan-Out-on-READ ❌"**
- Card corner radius 12, fill `--danger` at 6% opacity, 1 px stroke `--danger` at 30% opacity, padding 16 pt.
- Inside: a small node graph — one reader node on the left, 5 author nodes on the right, 5 arrows from reader → each author labelled "?". Below: "**500 reads per scroll** for a user following 500 people."

**RIGHT diagram — "Fan-Out-on-WRITE ✓ (ours)"**
- Card same style but `--success` at 6% opacity, stroke `--success` at 30%.
- Inside: one author node on left, 5 follower-timeline nodes on right, 5 arrows from author → each timeline, labelled "1×". Below: "**1 indexed query** against `feeds/{me}/timeline` regardless of follow count."

**BOTTOM — Code snippet** (full content width, 0.3 in below the two diagrams)
- Card: corner radius 8, fill `--code-bg`, padding 18 pt.
- JetBrains Mono 12 pt code with TypeScript syntax highlighting:
  ```ts
  // functions/src/posts.ts
  export const onPostCreate = onDocumentCreated(
    'posts/{postId}', async (event) => {
      const followers = await db.collection('users')
        .doc(authorUid).collection('followers').get();
      const batch = db.batch();
      for (const f of followers.docs) {
        batch.set(
          db.collection('feeds').doc(f.id)
            .collection('timeline').doc(postId),
          { postId, authorUid, createdAt },
        );
      }
      await batch.commit();  // batched in chunks of 450
    });
  ```

**Speaker notes:**
> "The hardest design question on a social app is how to efficiently build a user's home feed. Fan-out-on-read stores posts in one place and queries them by all the people you follow on every scroll — simple, but Firestore charges per read so a user following five hundred people pays five hundred reads per scroll. Fan-out-on-write inverts the problem: when an author posts, we immediately copy a pointer to that post into every follower's pre-computed timeline. The home screen then runs one indexed query, no matter how many people you follow. Writes get more expensive, but they happen far less often than reads. We batch in groups of four hundred and fifty because Firestore's limit is five hundred."

---

## Slide 11 — Notifications & Moderation (Mohammed) [Master B]

**Title:** "Two-Stage Notifications · Three-Layer Moderation"

**Layout:** Two equal columns 50/50.

**LEFT — Notification pipeline** (vertical step list)
- Header: "Two-Stage Notification Fan-Out" in 18 pt 600 Semibold `--ink-900`.
- Below, 4 numbered steps stacked vertically, each in a card (corner radius 8, fill `--surface-alt`, padding 12 pt). Step number in 14 pt 700 Bold `--primary`. Step text in 14 pt 400 `--ink-700`.
  1. User likes a post — `posts/{id}/likes/{uid}` write.
  2. `onLikeCreate` trigger writes `notifications/{authorUid}/items/{itemId}`.
  3. `onCreate` trigger on that doc → look up FCM tokens → format push.
  4. Push delivered via Firebase Cloud Messaging.

**RIGHT — Moderation layers** (vertical step list, same card style)
- Header: "Three-Layer Moderation" in 18 pt 600 Semibold `--ink-900`.
- 3 cards, each numbered 1–3:
  1. **Client filter** — words checked against Firestore-seeded list; flagged content marked `profanityFiltered: true`.
  2. **Server hook** — flagged messages skip the receiver's unread bump and push.
  3. **User reports** — four typed report collections, shape-validated, admin-only resolution.

**Speaker notes:**
> "Notifications work in two stages: first a Firestore document is written to the user's notification inbox, then a second trigger on that document fans out a push via Firebase Cloud Messaging. The two-stage design means the inbox stays consistent even when push delivery fails. Moderation is enforced in three layers — a client-side profanity filter, a server-side message hook that drops flagged chats from receiver notifications, and four typed report collections that only admins can resolve from the dashboard."

---

## Slide 12 — Verified-Partner Governance (Kaziwa) [Master B]

**Title:** "Trusted Content via Org-Admin Role"

**Layout:** Centered horizontal flow with 5 steps + role-boundary callout below.

**TOP — Flow (5 steps)**
- 5 circular nodes 48 px diameter, evenly spaced. Each node fill `--primary` at 12% opacity, 2 px stroke `--primary`, centered number in 16 pt 700 Bold `--primary`.
- Connected by 2 px solid lines `--ink-300`.
- Labels below each node in 13 pt 600 Semibold `--ink-900`, centered, max 2 lines:
  1. Organization submits `organization` contactRequest
  2. Admin reviews credentials
  3. `promoteToOrgAdmin` flips `role → org_admin`
  4. Rules let them create their own events
  5. Misbehavior → `revokeOrgAdmin`

**BOTTOM — Role boundary callout** (full-width card, 0.4 in below the flow)
- Card corner radius 12, fill `--surface-alt`, padding 18 pt, 1 px stroke `--ink-300`.
- Header: "Rules-Enforced Boundary" in 16 pt 600 Semibold `--ink-900`, with a small 16 px lock icon in `--success` to the left.
- Below, a code block: `allow create: if isOrgAdmin() && request.resource.data.createdByUid == request.auth.uid;` in JetBrains Mono 14 pt, on a `--code-bg` background card padded 12 pt, white-purple syntax highlight.
- Below the code, 8 pt gap, plain text in 14 pt 400 `--ink-700`: "Org-Admins can ONLY create events they themselves own. They cannot edit or delete events created by other partners — even with a decompiled APK."

**Speaker notes:**
> "Iter's promise of trustworthy content rests on a structured content-governance model. Opportunities aren't user-submitted — they come from verified partners. An organization opens a contact request of type organization, an admin reviews their credentials, and on approval the function promoteToOrgAdmin flips their user role from user to org-admin. Our Firestore rules then permit them to create events, but only events where the createdByUid equals their own UID — they cannot author content as anyone else. If they misbehave, revokeOrgAdmin instantly reverts their role. The enforcement is in the rules engine, server-side — not just the UI."

---

## Slide 13 — Agora Live + Supabase Uploads (Kaziwa) [Master B]

**Title:** "One Security Pattern, Two Integrations"

**Layout:** Two columns 50/50, each a self-contained mini-architecture.

**LEFT — Agora live**
- Header: "Agora Live Audio / Video" in 20 pt 600 Semibold `--ink-900`. Below, a 4-row sequence:
  1. User taps **Go Live**.
  2. Client → `live.issueLiveToken({ channelName, role })` Cloud Function.
  3. Function signs JWT with Agora secret (server-side env only) — TTL 1 h.
  4. Client joins channel · audio/video streams **peer-to-peer** via Agora.
- Each row a small card: 14 pt body, `--ink-700`, number circle on the left in `--primary` 14 pt 700, card fill `--surface-alt`, padding 10 pt.
- Below the rows, a small green pill (`--success` 12% opacity) 28 pt height containing: "✓ Agora secret never leaves the server."

**RIGHT — Supabase signed uploads** — identical pattern:
- Header: "Supabase Signed Uploads" in 20 pt 600 Semibold `--ink-900`.
- 4 rows:
  1. User picks photo.
  2. Client → Edge Function with Firebase ID token.
  3. Edge Function verifies token, signs one-time PUT URL with `service_role`.
  4. Client PUTs bytes **direct to Supabase Storage**.
- Bottom pill: "✓ Bytes never pass through our Cloud Function. URL is one-time."

**Speaker notes:**
> "Two integrations sharing the same security principle — never put a secret in the client. For Agora live rooms: the client calls our Cloud Function for a token, the function signs a JWT with the Agora app secret which lives only in the server environment, and the client joins the channel. From that point, audio and video stream peer-to-peer through Agora — never our backend. For Supabase uploads: the client calls our Edge Function with the Firebase ID token, the function verifies the token and signs a one-time upload URL with the service-role key, and the client PUTs bytes directly to Supabase Storage. Same pattern, different services: the secret stays server-side, short-lived tokens authorize the client just-in-time."

---

## Slide 14 — Translation, Push, Travel Mode (Kaziwa) [Master B]

**Title:** "Language Never Blocks Collaboration"

**Layout:** Three equal columns, each a feature card.

**CARD 1 — Translation**
- Corner radius 12, fill `--surface-alt`, padding 16 pt, 1 px stroke `--ink-300`.
- Top icon: 32 px Lucide **languages** icon in `--primary`.
- Below: title "Translation" in 18 pt 600 Semibold `--ink-900`, 6 pt gap.
- Body in 14 pt 400 `--ink-700`: "Server-side Google Gemini translation via `translate.ts`. Speech-to-text input (`speech_to_text`). Text-to-speech output (`flutter_tts`). Saved phrasebook under `users/{uid}/savedTranslations`."

**CARD 2 — Push Notifications**
- Same style. Icon: **bell** in `--primary`.
- Title: "FCM Push".
- Body: "Firebase Cloud Messaging via `notifications.ts` and `fcm_service.dart`. Notifications are two-stage: inbox document, then push fan-out, so the inbox stays consistent if push fails."

**CARD 3 — Travel Mode**
- Same style. Icon: **map-pin** in `--primary`.
- Title: "Travel Mode".
- Body: "Toggle `_nearbyMode` reads the user's GPS via `geolocator` and surfaces events within ~100 km. Extends Iter to international students and academic travelers without compromising privacy — GPS read only when user opts in."

**Speaker notes:**
> "Three more integrations round out the platform. Translation is powered by Google Gemini through a Cloud Function — speech-to-text in, translated text and text-to-speech out — so language never blocks cross-border collaboration. Saved translations build a personal academic phrasebook. Push notifications run on Firebase Cloud Messaging with the two-stage design we showed earlier. And travel mode reads the user's GPS only when they explicitly toggle it, surfacing events within a hundred kilometers — exactly the same distance threshold the personalization algorithm uses — so international students get a tailored local view."

---

## Slide 15 — Live Demo (Honya + Naz) [Master A]

**Layout:** Centered column on the brand gradient.

- Top center, 1.0 in from top: a 32 px Lucide **monitor-play** icon in `#FFFFFF`.
- Below the icon, 0.2 in gap: text "**LIVE DEMO**" in Inter 800 ExtraBold 56 pt, `#FFFFFF`, letter-spacing 2 px, centered.
- Below the title, 0.3 in gap: subtitle "10 steps · 90 seconds" in Inter 500 Medium 18 pt, `#FFFFFF` at 80% opacity, centered.
- Center area, 0.6 in below subtitle: a two-column list, 5 steps per column, evenly spaced. Each step is one line, 16 pt Inter 500 Medium, `#FFFFFF`. Step number in 16 pt 700 Bold `#FFFFFF` at 70% opacity, immediately followed by 14 pt 400 `#FFFFFF` at 90% opacity text:
  - Left column:
    1. Open app → Events tab.
    2. Point out top event (personalized).
    3. Toggle Travel Mode (Nearby).
    4. Home feed → like + comment.
    5. Create post with photo.
  - Right column:
    6. View a peer's Story.
    7. Open Discuss thread → react.
    8. Send voice message → react.
    9. Translate → TTS playback.
    10. Switch language → Arabic RTL.
- Bottom center, 0.5 in from bottom: in 12 pt 400 Regular `#FFFFFF` at 60% opacity: "Backup: `assets/demo.mp4` pre-recorded — always loaded on the laptop."

**Speaker notes:**
> "Let's show you the app live on a real phone — I'll mirror my screen to the projector. We're signed in as a seeded Demo Student account whose profile already has profession student, field tech, level undergraduate, and goals internships and hackathons. Watch the top of the events tab — the first event is a tech internship because the algorithm scored it highest. Then I'll toggle travel mode, walk through the feed, create a post, open a story, react in a discussion thread, send a voice message, translate a phrase to Kurdish with text-to-speech, and switch the entire UI to Arabic so you see the right-to-left flip. If anything fails we have a backup video on the laptop."

---

## Slide 16 — Tech Stack Summary (any presenter) [Master B]

**Title:** "Iter's Full Stack at a Glance"

**Layout:** 2 rows × 5 columns grid of feature tiles centered in the content area.

- Each tile: 2.0 in wide × 2.0 in tall, corner radius 12, fill `--surface-alt`, padding 14 pt, 1 px stroke `--ink-300`. 0.2 in horizontal gap, 0.2 in vertical gap.
- Each tile contains, vertically centered:
  1. A 32 px brand-style icon in `--primary` at the top.
  2. 8 pt gap, then the tech name in 14 pt 600 Semibold `--ink-900`, centered.
  3. 4 pt gap, then a one-line role descriptor in 11 pt 400 Regular `--ink-500`, centered, max 2 lines.

**Row 1 — Frontend & Identity**
1. Icon: **layers** · "Flutter" · "Android · iOS · Web"
2. Icon: **code** · "Dart" · "Language"
3. Icon: **shield-check** · "Firebase Auth" · "Email · Google · Apple"
4. Icon: **database** · "Cloud Firestore" · "Primary NoSQL store"
5. Icon: **server** · "Cloud Functions" · "Node 20 · TypeScript"

**Row 2 — Storage, Media, Messaging**
6. Icon: **cloud-upload** · "Supabase" · "Media storage"
7. Icon: **video** · "Agora RTC" · "Live audio / video"
8. Icon: **languages** · "Google Gemini" · "Translation"
9. Icon: **bell** · "FCM" · "Push notifications"
10. Icon: **activity** · "Realtime DB" · "Presence · typing"

**Speaker notes:**
> "Quick tech stack recap. Frontend is Flutter with Dart for Android, iOS, and web. Identity is Firebase Auth — email-password, Google, Apple. Database is Cloud Firestore as the primary store, with Realtime Database for live presence and typing. Ten Cloud Functions in Node twenty TypeScript provide the server-authoritative backend. Large media goes through Supabase signed-URL uploads. Live audio and video stream through Agora. Translation is powered by Google Gemini. Push notifications use Firebase Cloud Messaging. Everything is glued together by security rules and server-authoritative Cloud Functions, so clients can't fake state."

---

## Slide 17 — Q&A (all 5 on stage) [Master A]

**Layout:** Centered column on the brand gradient.

- Top center, 1.6 in from top: text "**Questions?**" in Inter 800 ExtraBold 88 pt, `#FFFFFF`, letter-spacing -1 px, centered.
- Below, 0.3 in gap: "Thank you." in Inter 500 Medium 28 pt, `#FFFFFF` at 75% opacity, centered.
- Center area, 0.8 in below "Thank you": 5 circular avatar placeholders horizontally arranged, each 96 px diameter, 2 px white stroke, fill `#FFFFFF` at 12% opacity, containing the team member's initial in Inter 700 Bold 36 pt `#FFFFFF`. Horizontal gap between circles 0.3 in.
- Below each circle, 0.2 in gap, the member's name in Inter 500 Medium 14 pt `#FFFFFF`, centered: **Honya · Naz · Zanyar · Mohammed · Kaziwa**.
- Bottom center, 0.4 in from bottom: in 12 pt 400 Regular `#FFFFFF` at 60% opacity: "Iter — Graduation Defense, 2026"

**Speaker notes:**
> "Thank you. We're happy to answer any questions. Whoever owns the most relevant slide will take the question first — if you'd like more detail we can open the actual code in the repository here on the laptop and walk through the implementation line by line."

---

# 3. OUTPUT REQUIREMENTS

1. Produce a **single `.pptx`** file with all **17 slides** above, in 16:9 widescreen (1920 × 1080 px).
2. Apply the **design system in §0 verbatim** — every color, font, size, spacing value is a hard requirement.
3. Each slide includes its **speaker-notes block** in the PowerPoint Notes pane, copied exactly as written.
4. Use the **two master slides** (A: full-bleed brand · B: content) as defined in §1.
5. Where the brief uses **`{{PLACEHOLDER}}`** strings (`{{SCREENSHOT: home_screen}}`, `{{DIAGRAM: feed_architecture}}`, etc.), insert a visible labeled rectangle of the exact size noted in the slide spec, filled with `--ink-300` at 20% opacity and the placeholder string centered in 12 pt monospace `--ink-500`. **Do not generate stock photos**.
6. All **footers, slide numbers, and master-slide chrome** are applied via Slide Master, not duplicated on each slide.
7. Icons referenced as **Lucide-style** (e.g. "monitor-play", "languages", "shield-check") should be rendered as **flat outlined line icons**, 2 px stroke, no fill, in the specified color. If your tooling cannot render Lucide icons, use the closest Material Outlined equivalent.
8. After generating, output a **summary table** listing each slide, its master, and any placeholder strings (`{{...}}`) the user needs to replace by hand before presenting.

End of prompt.

═══════════════════════════════════════════════════════════════════════════
