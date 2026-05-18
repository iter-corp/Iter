import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/e2ee/key_manager.dart';
import '../../theme/app_theme.dart';

/// Side-by-side display of the local user's pub-key fingerprint and the
/// peer's pub-key fingerprint. Two people in physical proximity can
/// read the codes out loud (or scan a future QR variant) to confirm
/// they hold each other's actual keys and not a MITM's. Accepting marks
/// the peer's current fingerprint as trusted via
/// [KeyManager.acknowledgePeerKey], dismissing the security-code-
/// changed banner.
class SecurityVerificationScreen extends ConsumerWidget {
  final String peerUid;
  final String peerName;

  const SecurityVerificationScreen({
    super.key,
    required this.peerUid,
    required this.peerName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meUid = ref.watch(authStateProvider).value?.uid;
    if (meUid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verify security code')),
        body: const Center(child: Text('Not signed in.')),
      );
    }
    final km = ref.watch(keyManagerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Verify security code')),
      body: FutureBuilder<(String?, String?)>(
        future: () async {
          final mine = await km.fingerprintForSelf(meUid);
          final theirs = await km.fingerprintForPeer(peerUid);
          return (mine, theirs);
        }(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final mine = snap.data!.$1;
          final theirs = snap.data!.$2;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.verified_user_outlined,
                      size: 40, color: AppColors.purple),
                  const SizedBox(height: 12),
                  Text(
                    'Verify $peerName',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Compare these codes with $peerName in person or over '
                    'another trusted channel. If they match on both sides, '
                    'no one has tampered with your encryption keys.',
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _CodeBlock(
                    label: 'Your code',
                    code: mine ?? 'unavailable',
                  ),
                  const SizedBox(height: 12),
                  _CodeBlock(
                    label: '$peerName\'s code',
                    code: theirs ?? 'unavailable',
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: theirs == null
                          ? null
                          : () async {
                              await km.acknowledgePeerKey(
                                meUid: meUid,
                                peerUid: peerUid,
                              );
                              ref.invalidate(
                                  peerKeyStateProvider('$meUid|$peerUid'));
                              if (context.mounted) {
                                Navigator.of(context).pop(true);
                              }
                            },
                      child: const Text('Mark as verified'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String label;
  final String code;
  const _CodeBlock({required this.label, required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            code,
            style: TextStyle(
              fontSize: 15,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
