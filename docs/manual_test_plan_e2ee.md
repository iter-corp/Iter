# Manual Test Plan — E2EE Lifecycle

Covers the four-session encryption work: hybrid chats, recovery password
UX, multi-device detection, security-code verification, group
missing-key warnings, send-flow stability fixes, and the plaintext
message cache.

Run on a real Android device (the SM A505F we used during development
works). Each scenario has setup, the actions to perform, and what you
should see. **Mark each ✅ or ❌ — anything ❌ is a real bug to fix
before shipping.**

## Prep

1. `flutter clean && flutter pub get && flutter run -d RZ8M73FHH3P`
2. Make sure you have a second account, or a willing friend on a second
   device — most scenarios need a peer.
3. Open DevTools or watch `flutter logs` so you can see the `[e2ee]`,
   `[chat-cache]`, `[signout-cleanup]` debug prints.

---

## Scenario A — Hybrid chat: normal vs secret

### A1. Default new chat is plaintext-on-server
1. Open another user's profile.
2. Tap (don't long-press) the **Message** button.
3. Send "hello world".
4. In Firebase console → Firestore → `chats/{id}/messages/{id}` →
   check the doc. `text` should be `"hello world"`, no `enc` field.
5. **Expected**: no lock icon in the chat header. Inbox tile has no
   lock.

### A2. Opt-in secret chat
1. From a different user's profile, **long-press** Message.
2. Sheet appears with "Normal chat" / "Secret chat".
3. Tap "Secret chat". (First time only: you'll be routed through Set
   Recovery Password — see C1.)
4. Send "secret hello".
5. In Firestore: `enc` field present, `text` is `""`, `lastMessage` is
   `"🔒 Encrypted message"`.
6. **Expected**: lock icon in header next to peer name. Lock icon on
   inbox tile. Tapping the header lock opens the verification screen.

### A3. Existing chats stay encrypted (no downgrade)
1. Open a chat you had before this build.
2. Send a message.
3. **Expected**: still encrypted (`enc` field on new message). Header
   shows the lock.

---

## Scenario B — Sign-out cleanup

### B1. Local plaintext cache is wiped
1. Sign in as User A, open 2-3 chats so the message cache populates.
2. Verify: `flutter logs` should show no `MessageCache.clearAll` line
   yet.
3. Sign out (Settings → sign out, or whatever the entry point is in
   your app).
4. **Expected**: `[signout-cleanup]` debug lines for `deleteLocal`,
   `e2ee.clearCache`, `MessageCache.clearAll`. No errors.
5. Sign in as User B on the same device.
6. Open the inbox.
7. **Expected**: no plaintext from User A's chats appears anywhere.
   Inbox tile previews don't show A's last messages.

---

## Scenario C — Recovery password flows

### C1. First-secret-chat prompts for password
1. Fresh install (or sign out + clear app data + sign in).
2. Long-press Message → Secret chat.
3. **Expected**: routed to "Set recovery password" screen *before* the
   chat opens.
4. Enter a password under 8 chars → "Password must be at least 8
   characters."
5. Enter mismatched confirm → "Passwords do not match."
6. Enter valid + matching → "Save password" → returns to chat creation
   flow → chat opens.

### C2. Settings entry rotates the password
1. Settings → Encryption → Secret-chat recovery password.
2. Set a different new password.
3. **Expected**: success, no error.
4. Restart the app.
5. Open the secret chat from C1 — old messages should still decrypt
   (the *recovery* password changed, not the device keypair).

### C3. Legacy-user inbox banner
1. Find a user who already has the app installed from before this
   update (or simulate by deleting the `e2ee.recovery.userset.<uid>`
   entry from secure storage — easier: just don't complete C1).
2. Open the inbox.
3. **Expected**: purple "Protect your secret chats" banner at top with
   "Set password" / "Not now" buttons.
4. Tap "Not now". Banner disappears for this session.
5. Force-quit the app and reopen.
6. **Expected**: banner reappears (per-session dismissal).
7. Now tap "Set password" → completes the flow.
8. **Expected**: banner never appears again on any session.

---

## Scenario D — Restore on new device / reinstall

### D1. Reinstall sees the restore banner
1. As User A, set a recovery password (C1) and send a few messages in
   a secret chat with User B.
2. **Uninstall** the app from User A's device (not just sign out —
   full uninstall, so Keystore wipes).
3. Reinstall. Sign in as User A.
4. **Expected**: purple "Restore your encrypted chat history" banner
   at the top of the routed app.
5. Tap it → restore screen → type the recovery password from C1 →
   "Unlock".
6. **Expected**: banner dismisses. Open the User B chat — old messages
   should decrypt.

### D2. Wrong password is rejected
1. Same setup as D1.
2. Type a deliberately wrong password.
3. **Expected**: "Wrong password. Try again, or reset encryption."

### D3. Forgot-password reset accepts losing history
1. Same setup, type wrong password, then tap "I forgot my password —
   reset encryption."
2. Confirmation dialog → "Reset".
3. **Expected**: routed to the reset screen → tap "Reset encryption"
   → returns to inbox.
4. Old secret-chat messages stay locked (🔒 bubble). Sending a new
   message in the same chat works.
5. From User B's side, after User B re-opens the chat, the next
   message User A sends should decrypt for B.

---

## Scenario E — Multi-device collision

### E1. Sign in on a second device → original gets banner
1. As User A, sign in on Device 1. Send some messages.
2. Without signing out, sign in as User A on Device 2.
3. Wait ~10 seconds (Device 2 generates and publishes a new pub).
4. Force-resume Device 1 (background then foreground the app).
5. **Expected**: Device 1's `KeySyncState` flips to
   `replacedByOtherDevice` (visible via the multi-device detection —
   currently no UI banner, only the state provider; tap a 🔒 bubble in
   an existing secret chat to see the "Encryption key was replaced"
   sheet copy).

---

## Scenario F — Security-code-changed banner

### F1. Peer reinstall triggers the amber banner
1. As A, in a secret chat with B, scroll through history (this stores
   B's fingerprint on A's device).
2. Have B uninstall + reinstall + restore (or reset).
3. B's pub will change → published key differs from what A stored.
4. A opens the chat.
5. **Expected**: amber bar above the message list: "B's security code
   changed. Tap to verify."
6. Tap → verification screen showing A's and B's codes side by side.
7. Tap "Mark as verified" → banner disappears.
8. Reload the chat: banner should not reappear.

---

## Scenario G — Group missing-key warning

### G1. Member without published key
1. Create a small group with 2-3 members.
2. Manually delete one member's `publicKey` from Firestore (or invite
   a brand-new user who hasn't opened the app yet — they won't have
   published one).
3. Mark the group as `secret: true` in Firestore (no UI for secret
   groups yet).
4. Open the group chat.
5. **Expected**: amber warning above the composer: "Alice won't be
   able to read this message until they open the app on a device with
   encryption set up."
6. Send a message anyway — it sends, that person's bubble shows 🔒.

---

## Scenario H — Send flow stability

### H1. Permission denied keeps the typed text
1. Be in a group with `restrictMessaging: true` where you're not
   admin.
2. Type a long message.
3. Tap send.
4. **Expected**: snackbar "Messaging is restricted in this group".
   **Your text is still in the input box.**

### H2. Network failure restores reply context
1. Open a chat, long-press a message → Reply.
2. Type a message in the composer (with the reply preview visible).
3. Enable Airplane Mode.
4. Tap send.
5. **Expected**: snackbar "Failed to send message". Text is back in
   the input. Reply preview is still visible above the composer.

### H3. Double-tap doesn't send twice
1. Tap send rapidly twice on a normal text message during a slow
   network (throttle in Chrome DevTools if you can, or just on a real
   cold-start).
2. **Expected**: exactly one message in the chat, not two.

### H4. Keyboard stays open after sending
1. Type a message → send.
2. **Expected**: keyboard does NOT auto-dismiss. You can immediately
   type the next message.

---

## Scenario I — Chat-open performance

### I1. Second open is instant
1. Open a chat with 100+ messages. First open: notice the loading
   time (network + decrypt).
2. Back out, reopen the same chat.
3. **Expected**: last 20 messages render immediately, no loading
   spinner. Older ones load as you scroll up.

---

## What's NOT covered by this plan
Out-of-scope or hard to test manually:

- Backend (Firestore Cloud Functions) — none of these changes touched
  the backend.
- The fingerprint distribution math (covered by the code review).
- Cache race under extreme stress — would need an instrumented test.
- The session-1 `MessageCache` already shipped — assumed working.

---

## Priority

**Must-pass before any user sees this:** A, B, C, D, H1-H4, I1.

**Deeper / product-team validation:** E, F, G.
