# Profile and User

## What this feature does
Two related top-level screens render a user:
- `ProfileScreen` — the **viewer's own** profile (current user). 4 outer tabs: **Posts / Discuss / Reposts / Saved**, where the Discuss tab has 2 inner pill tabs **Threads started / Replies** (asked vs answered).
- `UserProfileScreen` (`user_screen.dart`) — **another user's** profile. Same outer tab pattern minus Saved, plus Follow/Unfollow, Block/Unblock, Report, Direct Message, with visibility rules (`isPrivate`, blocked-by, blocking).

Editing happens in `EditProfileScreen` (avatar + cover, name, bio, gender, profession, field, academic level, goals, plus toggles). Settings live in `ProfileSettingsScreen` with sub-flows: Change Email, Change Password (only for email/password users), Language, Theme, Blocked Users, Profile Visitors, Event Notifications, Contact Us, Saved Translations, Logout, Delete Account. `ProfileVisitorsScreen` shows recent visitors to the user's own profile. `personalization_fields.dart` exports the shared `AboutYouEditor` used in both onboarding and edit-profile.

## Key screens / widgets
- [profile_screen.dart](../../lib/src/features/screens/profile_screen.dart) — owner profile with 4-tab layout, horizontal swipe to switch tabs (250 px/s threshold), `UserQaActivitySection` for Discuss with inner `Threads started / Replies` tabs.
- [user_screen.dart](../../lib/src/features/screens/user_screen.dart) — other user's profile.
- [edit_profile.dart](../../lib/src/features/screens/edit_profile.dart) — full edit form.
- [profile_settings_screen.dart](../../lib/src/features/screens/profile_settings_screen.dart) — settings list; modular sections (account / appearance / language / safety / danger zone).
- [profile_visitors_screen.dart](../../lib/src/features/screens/profile_visitors_screen.dart) — visitors list.
- [change_password_screen.dart](../../lib/src/features/screens/change_password_screen.dart) — current/new password form.
- [profile_widget.dart](../../lib/src/features/widgets/profile_widget.dart) — owner profile parts: `ProfileCoverAvatar`, `ProfileNameBio`, `ProfileStats`, `ProfileButtons`, `ProfileTabBar`, `ProfileEmpty`, `ProfileBottomNav`.
- [user_profile_widget.dart](../../lib/src/features/widgets/user_profile_widget.dart) — other-user profile parts.
- [personalization_fields.dart](../../lib/src/features/widgets/personalization_fields.dart) — `AboutYouEditor`, `CityPickerField`, `academicLevelAppliesTo(profession)`.

## Profile fields (`users/{uid}` doc)
- Identity: `uid`, `email`, `username`, `usernameLower`, `handle` (`@username`).
- Display: `name`, `bio`, `avatarUrl`, `coverUrl`, `gender`, `city`, `location: {lat, lng}`.
- Personalization: `profession`, `field`, `academicLevel` (only when `academicLevelAppliesTo(profession)`), `goals: List<String>`.
- RBAC: `role` (`user`, `admin`, `org_admin`, etc.), `suspended`.
- Privacy: `isPrivate` (bool), `appIntroSeen`.
- Counters: `followersCount`, `followingCount`, `postsCount`.
- Devices: `fcmTokens: List<String>` (registered for push).
- Notification prefs: `eventNotifPrefs: {mode, types, countries}`.
- `createdAt`.

## Outer profile tabs (owner)
1. **Posts** — `UserPostsGrid(uid)`. Grid of `PostThumbTile`s.
2. **Discuss** — `UserQaActivitySection(uid)`. Inner pill toggle:
   - **Threads started** (`userQaAskedProvider`) — Q&A topics the user authored.
   - **Replies** (`userQaAnsweredProvider`) — Q&A threads where the user has an answer (`highlightAuthorUid: widget.uid` pins their answer when opening `QaThreadScreen`).
3. **Reposts** — `UserRepostsGrid(uid)`.
4. **Saved** — `UserSavedGrid(uid)` (owner only).

Horizontal swipe between tabs (left = next, right = prev, 250 px/s velocity threshold). `AnimatedSwitcher` cross-fade + 4% slide between tabs.

## Other-user profile (`UserProfileScreen`)
- Tabs: Posts, Discuss, Reposts (no Saved — not visible to others).
- Action row: Follow / Unfollow / Requested (private accounts), Message (`openChat`), Report, Block.
- Visibility:
  - If the viewer is blocked by the owner OR the owner has blocked the viewer → block screen.
  - If `isPrivate` and the viewer isn't a follower → locked tab content with `profileOnlyFollowersCanSee` message.
- The `_followBusy` flag debounces rapid follow taps.
- Report flow (`_reportProfile`) writes to `userReports` via `UserService.reportUserProfile`.

## Follow system
- Provider tree: `followersProvider(uid)`, `followingProvider(uid)`.
- For private accounts the follow button transitions Follow → Requested → Following.
- `FollowService.follow / unfollow / cancelRequest`.
- `followersCount` / `followingCount` are denormalized on the user doc and counter-checked against the subcollection length for display.

## Block system
- `BlockService.blockUser` / `unblockUser`.
- `block_providers.dart` exposes both directions of the relation.
- Effects: blocked user can't see this profile, can't open chat, can't comment/reply on this user's posts. The other-user screen renders an empty state with an Unblock CTA when the viewer is the blocker, or a blank lock when the viewer is blocked.

## Profile visitors
- `ProfileVisitorService.recordVisit` writes `users/{ownerUid}/visitors/{visitorUid}` when the viewer is not the owner.
- `ProfileVisitorsScreen` lists the most recent visitors with tap-through. The count provider streams the size of the visitors subcollection.

## Settings (`ProfileSettingsScreen` sections)
- **Account**
  - Change email — only for email/password users. `_isEmailPasswordUser` checks `providerData.any((p) => p.providerId == 'password')`. Otherwise a dialog says it can't be changed.
  - Change password — opens `ChangePasswordScreen`.
- **Notifications** — Event notifications → `EventNotificationsSettingsScreen`.
- **Appearance** — Theme toggle via `themeProvider`.
- **Language** — `_languageLabel` resolves `preferredLanguageProvider` against `kTranslateLanguages`; tapping opens `/language` route.
- **Safety** — Blocked users (`BlockedUsersScreen`), Profile visitors.
- **Help** — Contact us, Saved translations, Share app.
- **Danger zone** — Logout (clears `adminConfigProvider`, `adminPostsProvider`, `adminEventsProvider`, `blacklistProvider` and routes to `/login`). Delete account (`_confirmDeleteAccount`).

## Firestore collections touched
- `users/{uid}` — profile doc.
- `users/{uid}/following`, `users/{uid}/followers` — relations.
- `users/{uid}/visitors` — profile visits.
- `users/{uid}/blocks` — blocked uids.
- `users/{uid}/saved`, `users/{uid}/reposts` — owner-only grids.
- `userReports` — profile reports.
- `posts` — queried by author for the Posts grid; filtered by `discussKind` for the Discuss tab.
- `contactRequests` (settings → contact us).

## Services used
- [user_service.dart](../../lib/src/services/user_service.dart) — `streamUser`, `updateUser`, `isUsernameTaken`, `setEventNotifPrefs`, `reportUserProfile`, `deleteAccount`.
- [follow_service.dart](../../lib/src/services/follow_service.dart) — `follow`, `unfollow`, `cancelRequest`, `acceptRequest`.
- [block_service.dart](../../lib/src/services/block_service.dart) — `blockUser`, `unblockUser`.
- [profile_visitor_service.dart](../../lib/src/services/profile_visitor_service.dart) — `recordVisit`, `streamVisitors`.
- [storage_service.dart](../../lib/src/services/storage_service.dart) — `uploadAvatar`, `uploadCover`.
- [auth_service.dart](../../lib/src/services/auth_service.dart) — `signOut`.
- [translate_service.dart](../../lib/src/services/translate_service.dart) — `kTranslateLanguages` constant used by the language picker.

## Non-obvious business rules
- Avatar / cover edits are uploaded only when changed; the form keeps `_avatarUrl` / `_coverUrl` as either the original network URL or a freshly uploaded URL.
- `_matchOption(value, options)` snaps a stored value to one of the admin-defined options to handle legacy values when options change.
- `academicLevel` is written even if reset (empty string) so syncing with profession works deterministically.
- The owner Posts grid uses `postsCount` as a fallback; the actual list is `userPostsProvider`.
- The horizontal swipe to switch tabs uses `primaryVelocity` not delta to filter accidental vertical-scroll drift.
- Owner profile defaults the "Saved" tab visible to the owner only (others get only 3 tabs).
- `ProfileSettingsScreen` invalidates the admin / blacklist providers on logout so a re-login with a different role sees fresh data.
- Change email refuses non-email/password providers (Google / Apple users redirect to their provider).
- Profile visitors does not exist on private accounts that haven't opted in — `myProfileVisitorsProvider` returns empty if no visits.
- For `_reportProfile`: reports authors cannot report themselves (`canReport = currentUid != post.authorUid`).

## Localization
- `profile_screen.dart`: ~43 keys.
- `user_screen.dart`: ~41.
- `profile_settings_screen.dart`: ~67.
- `edit_profile.dart`: ~26.
- `profile_visitors_screen.dart`: ~8.
- `change_password_screen.dart`: ~18.
- `profile_widget.dart`: ~8.
- `user_profile_widget.dart`: ~10.

## Related files
- `lib/src/features/screens/profile_screen.dart`
- `lib/src/features/screens/user_screen.dart`
- `lib/src/features/screens/edit_profile.dart`
- `lib/src/features/screens/profile_settings_screen.dart`
- `lib/src/features/screens/profile_visitors_screen.dart`
- `lib/src/features/screens/change_password_screen.dart`
- `lib/src/features/screens/blocked_users_screen.dart`
- `lib/src/features/widgets/profile_widget.dart`
- `lib/src/features/widgets/user_profile_widget.dart`
- `lib/src/features/widgets/personalization_fields.dart`
- `lib/src/services/user_service.dart`
- `lib/src/services/follow_service.dart`
- `lib/src/services/block_service.dart`
- `lib/src/services/profile_visitor_service.dart`
- `lib/src/services/storage_service.dart`
- `lib/src/providers/follow_providers.dart`
- `lib/src/providers/block_providers.dart`
- `lib/src/providers/profile_visitor_providers.dart`
- `lib/src/providers/preferred_language_provider.dart`
- `lib/src/providers/theme_provider.dart`
