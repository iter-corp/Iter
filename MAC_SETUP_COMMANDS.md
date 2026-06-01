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

### Quick check: which branch am I on?

```bash
git branch
```

The branch with `*` next to it is the one you're building.
It MUST be `* M-newUI-multiL`.
