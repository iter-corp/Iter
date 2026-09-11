---
name: group-commits
description: >-
  Use this skill whenever the user asks to group commits, split pending changes into backend and
  frontend commits, validate code errors before committing, fix errors, or create clean atomic commits.
---

# Group Commits with Error Validation and Auto-Fixing

This skill provides a systematic runbook for inspecting uncommitted changes, partitioning them into logical atomic commits (with primary separation between **Backend** and **Frontend**), validating code against static analysis and build errors, fixing any errors automatically, and executing atomic Git commits.

## Workflow Overview

```
[Inspect Working Tree]
         │
         ▼
[Group Changes: Backend First, Frontend Second, Config/Docs Third]
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│ For Each Logical Group:                                 │
│                                                         │
│ 1. Validate Code (TypeScript build / Flutter analyze)  │
│ 2. Fix Errors immediately if detected                   │
│ 3. Re-validate until clean                              │
│ 4. Stage ONLY files in this group (`git add <files>`)   │
│ 5. Commit with Conventional Commits                     │
└─────────────────────────────────────────────────────────┘
         │
         ▼
[Verify Clean Working Tree & Display Commit Log]
```

---

## Step 1: Inspect and Group Changes

1. Run the change classification script or inspect `git status -s`:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .agents/skills/group-commits/scripts/classify_changes.ps1
   ```
   Or directly:
   ```bash
   git status -s
   ```

2. Separate the changes according to the **Primary Partition Hierarchy**:

### Primary Priority 1: Backend
Group backend changes into atomic subsets in this order:
- **`backend/db`**: Database schemas, relations, migrations (`backend-hono/src/db/schema/*`, `backend-hono/src/db/migrations/*`, `backend-hono/src/db/index.ts`, `backend-hono/src/db/migrate.ts`).
- **`backend/routes`**: API endpoints, middleware, controllers, routes (`backend-hono/src/routes/*`, `backend-hono/src/app.ts`).
- **`backend/services` & `backend/config`**: Backend helpers, configs, scripts (`backend-hono/src/config/*`, `backend-hono/src/scripts/*`, `backend-hono/package.json`).
- **`backend/functions` & `backend/rules`**: Firebase Functions, security rules (`functions/*`, `firestore.rules`, `storage.rules`, `database.rules.json`, `supabase/*`).
- **`test(backend)`**: Backend tests (`backend-hono/test/*`).

### Primary Priority 2: Frontend (Flutter / Native)
Group frontend changes into atomic subsets in this order:
- **`frontend/services` & `frontend/providers`**: State management, business logic, API clients (`lib/src/services/*`, `lib/src/providers/*`).
- **`frontend/core`**: Entrypoint, navigation, theme, core utilities (`lib/main.dart`, `lib/src/core/*`).
- **`frontend/screens`**: UI pages and screens, grouped by domain (e.g., admin, profile, events, home) (`lib/src/features/screens/*`).
- **`frontend/widgets`**: Reusable UI components (`lib/src/features/widgets/*`).
- **`frontend/l10n`**: Localization strings and language files (`lib/src/l10n/*`).
- **`frontend/platform`**: Android/iOS/Web configuration (`android/*`, `ios/*`, `web/*`, `windows/*`, `macos/*`, `linux/*`, `assets/*`).
- **`test(frontend)`**: Widget and unit tests (`test/*`).

### Primary Priority 3: Config, DevOps & Documentation
- **`chore(config)`**: Root configuration (`ecosystem.config.json`, `firebase.json`, `pubspec.yaml`, `analysis_options.yaml`, `.gitignore`).
- **`docs`**: Documentation guides and notes (`*.md`, `*.txt`, `docs/*`).

> [!WARNING]
> **Exclude Build Artifacts**: Never commit compiled or temporary artifacts (e.g. `backend-hono/dist/`, `build/`, `.dart_tool/`, `backend-hono/uploads/`). Add them to `.gitignore` if untracked.

---

## Step 2: Validate and Auto-Fix Errors

Before committing any group, perform rigorous validation. **Do not create a commit with compilation or analyzer errors.**

### Backend Validation (Node / TypeScript / Hono)
When committing backend files:
1. Navigate to `backend-hono` and run TypeScript compilation:
   ```powershell
   npm --prefix backend-hono run build
   ```
2. If errors are reported:
   - Identify the file path and line number from the TypeScript compiler output.
   - Inspect the issue (type mismatch, missing import, route definition, schema mismatch).
   - Edit the code to fix the error.
   - Re-run `npm --prefix backend-hono run build` until 0 errors are found.
3. If backend test files are modified:
   ```powershell
   npm --prefix backend-hono test
   ```
   Fix any failing assertions or mock requirements.

### Cloud Functions Validation (if `functions/` modified)
1. Run compilation in `functions/`:
   ```powershell
   npm --prefix functions run build
   ```
2. Fix any syntax or type issues.

### Frontend Validation (Flutter / Dart)
When committing frontend files:
1. Run static analysis from workspace root:
   ```powershell
   dart analyze lib test
   ```
   Or:
   ```powershell
   flutter analyze
   ```
2. If analyzer errors or serious warnings occur on modified files:
   - Read the diagnostic message and target file/line.
   - Fix missing arguments, null-safety issues, invalid imports, or deprecated API calls.
   - Re-run `dart analyze lib test` until all errors in the affected files are resolved.
3. If tests in `test/` were modified or added:
   ```powershell
   flutter test <modified_test_file>
   ```

---

## Step 3: Atomic Staging and Commits

For each logical group defined in Step 1:

1. **Stage ONLY the group's files**:
   ```bash
   git add <file1> <file2> ...
   ```
   *Never* run `git add .` or `git add -A` when creating split group commits.

2. **Verify Staged Files**:
   ```bash
   git status
   ```
   Ensure only the intended files for this specific group are green (staged).

3. **Format Conventional Commit Message**:
   Follow standard Conventional Commits:
   `<type>(<scope>): <imperative description>`

   Examples:
   - `feat(backend/db): Add dynamic events and admin schema tables`
   - `feat(backend/routes): Support dynamic event queries in events route`
   - `test(backend): Add user isolation test suite`
   - `refactor(frontend/services): Migrate wikimedia feed service to http client`
   - `feat(frontend/screens): Update event screen with dynamic type filters`
   - `feat(frontend/l10n): Add Kurdish and Arabic localization strings`
   - `docs: Add Hostinger deployment guide`
   - `chore(config): Update PM2 ecosystem config`

4. **Commit**:
   ```bash
   git commit -m "<commit message>"
   ```

---

## Step 4: Final Verification

1. Check that the working tree is completely clean (or only has intended ignored files):
   ```bash
   git status
   ```
2. Display the list of commits created during the session:
   ```bash
   git log -n <number_of_groups> --oneline
   ```
3. Report the grouped summary clearly to the user with commit hashes and scopes.
