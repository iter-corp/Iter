import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/e2ee/key_manager.dart';
import '../../theme/app_theme.dart';

/// Set-or-rotate the recovery password used to encrypt the user's
/// cross-device recovery key backup. Opened the first time the user
/// starts a secret chat, and reachable from settings.
///
/// Migration semantics: until the user completes this screen, the
/// recovery key is encrypted with a uid-derived password (anyone who
/// learns a uid can decrypt the cloud backup). Completing this screen
/// re-encrypts the backup with their chosen password and flips the
/// `hasUserChosenRecoveryPassword` flag.
class SetRecoveryPasswordScreen extends ConsumerStatefulWidget {
  const SetRecoveryPasswordScreen({super.key});

  @override
  ConsumerState<SetRecoveryPasswordScreen> createState() =>
      _SetRecoveryPasswordScreenState();
}

class _SetRecoveryPasswordScreenState
    extends ConsumerState<SetRecoveryPasswordScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pass.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) {
      setState(() => _error = 'Not signed in.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final km = ref.read(keyManagerProvider);
    final hasChosen = await km.hasUserChosenRecoveryPassword(uid);
    final oldPassword = hasChosen
        ? await km.resolveRecoveryPassword(uid)
        : KeyManager.legacyPasswordFor(uid);
    try {
      final ok = await km.setRecoveryPassword(
        uid: uid,
        oldPassword: oldPassword,
        newPassword: pass,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = 'Could not rotate recovery password — try again.';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set recovery password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline,
                  size: 40, color: AppColors.purple),
              const SizedBox(height: 12),
              Text(
                'Pick a recovery password',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This password protects your encrypted chat history when you '
                'sign in on a new device. You will need it to read old '
                'secret-chat messages after a reinstall.\n\n'
                'Coil cannot recover this password for you. If you lose it, '
                'old encrypted messages will be unreadable.',
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown on app startup when the device has no local private key but
/// Firestore advertises a recovery backup for this account — e.g. a
/// fresh reinstall or first sign-in on a new device. Prompts for the
/// recovery password, unlocks the backup, and (on success) republishes
/// the device's pub so other senders start wrapping for it.
class RestoreEncryptionScreen extends ConsumerStatefulWidget {
  const RestoreEncryptionScreen({super.key});

  @override
  ConsumerState<RestoreEncryptionScreen> createState() =>
      _RestoreEncryptionScreenState();
}

class _RestoreEncryptionScreenState
    extends ConsumerState<RestoreEncryptionScreen> {
  final _passCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _passCtrl.text;
    if (pass.isEmpty) return;
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final km = ref.read(keyManagerProvider);
    final e2ee = ref.read(e2eeServiceProvider);
    try {
      // Generate/republish the device keypair first so other devices
      // start wrapping for us. The recovery-key fallback lets us
      // unlock messages encrypted before this device existed.
      await km.ensureKeyPair(uid);
      final priv = await km.loadRecoveryKey(uid, pass);
      if (priv == null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'Wrong password. Try again, or reset encryption.';
        });
        return;
      }
      final ok = await e2ee.unlockRecoveryKey(uid, pass);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = 'Could not unlock recovery key. Try again.';
        });
        return;
      }
      // Refresh the multi-device check now that we've republished.
      ref.invalidate(keySyncCheckProvider(uid));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Failed: $e';
      });
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Reset encryption?'),
          content: const Text(
            'This will generate a fresh encryption key on this device. '
            'You will not be able to read any past secret-chat messages, '
            'but you can start new ones. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ResetEncryptionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restore encryption')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_open_outlined,
                  size: 40, color: AppColors.purple),
              const SizedBox(height: 12),
              Text(
                'Enter your recovery password',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This device does not have your encryption key yet. Enter '
                'the recovery password you set previously to unlock your '
                'secret-chat history.',
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Recovery password',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Unlock'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _confirmReset,
                child: const Text('I forgot my password — reset encryption'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Last resort: wipe the local keypair + stashed password and
/// regenerate. The user accepts losing access to old secret-chat
/// messages encrypted with the previous keys. Used when the user
/// forgot their recovery password and can't unlock the backup.
class ResetEncryptionScreen extends ConsumerStatefulWidget {
  const ResetEncryptionScreen({super.key});

  @override
  ConsumerState<ResetEncryptionScreen> createState() =>
      _ResetEncryptionScreenState();
}

class _ResetEncryptionScreenState
    extends ConsumerState<ResetEncryptionScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _reset() async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(keyManagerProvider).resetEncryptionIdentity(uid);
      ref.invalidate(keySyncCheckProvider(uid));
      if (!mounted) return;
      // Pop back to whatever entry triggered the reset.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Reset failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset encryption')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                'Reset your encryption key?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This will generate a brand-new encryption key on this '
                'device. Any past secret-chat messages you have not been '
                'able to decrypt will stay unreadable.\n\n'
                'New secret chats — and new messages in existing ones — '
                'will work normally as soon as the other person opens the '
                'chat again.',
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _busy ? null : _reset,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Reset encryption'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
