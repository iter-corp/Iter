# Mac Setup — Get the New Features Running

The new features (follow list, admin suite, account center, etc.) live on the
branch **`M-newUI-multiL`**, NOT on `main`. On the Mac you were building `main`,
which is older code WITHOUT these features.

Run these commands on the Mac to fix it.

## 1. Switch to the correct branch and pull latest

```bash
git fetch origin
git checkout M-newUI-multiL
git pull origin M-newUI-multiL
```

## 2. Verify you're on the right code

```bash
git log -1 --oneline
```

✅ It MUST show: `6a1494f ios`
If it shows anything else (like `618dc77 a`), you are on the wrong branch.

## 3. Clean and rebuild

```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter run
```

---

## ✅ Pre-Build Checklist (do this BEFORE you rebuild on Mac)

Tick each item. Do NOT rebuild until all are checked.

- [ ] **On the right branch** — run `git branch`, the `*` is on `M-newUI-multiL`
- [ ] **Latest commit is correct** — run `git log -1 --oneline`, it shows `6a1494f ios`
- [ ] **All 10 commits are present** — run `git log -10 --oneline` and confirm you see:
  - [ ] `6a1494f ios`
  - [ ] `81248fa m`
  - [ ] `755d049 update`
  - [ ] `b7dcd9a a`
  - [ ] `264d4b2 update`
  - [ ] `963506f M`
  - [ ] `c7f5933 up M`
  - [ ] `74549e2 up`
  - [ ] `cb4b567 update`
  - [ ] `9d544db M`
- [ ] **New feature files exist** — confirm these files are present:
  - [ ] `lib/src/features/screens/follow_list_screen.dart`
  - [ ] `lib/src/features/screens/account_center_screen.dart`
  - [ ] `lib/src/features/screens/change_email_screen.dart`
  - [ ] `lib/src/features/screens/admin/admin_api_manager_screen.dart`
  - [ ] `lib/src/services/city_service.dart`
- [ ] **No uncommitted surprises** — run `git status`, working tree is clean
- [ ] **In sync with GitHub** — run `git pull origin M-newUI-multiL`, it says "Already up to date"

When ALL boxes are checked → run the clean rebuild in step 3 above.

---

### One-line check: am I on the right code?

```bash
git branch --show-current && git log -1 --oneline
```

Expected output:
```
M-newUI-multiL
6a1494f ios
```
