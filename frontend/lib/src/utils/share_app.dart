import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../services/admin_service.dart';
import 'app_feedback.dart';
import 'package:flutter/material.dart';

/// Opens the native share sheet so a user can invite friends to install Iter.
///
/// Picks the store link for the running platform from [AdminConfig]
/// (iOS → App Store, Android → Google Play), falling back to the other store
/// link, and finally to a generic message if neither is configured by the
/// admin yet.
Future<void> shareInviteLink(BuildContext context, AdminConfig config) async {
  final link = _storeLinkForPlatform(config);

  if (link == null || link.isEmpty) {
    AppFeedback.showInfo(
      context,
      'The app store link isn\'t set up yet — check back soon!',
    );
    return;
  }

  final message = 'Join me on Iter — connect with students, researchers and '
      'travellers, discover events and more:\n$link';

  // share_plus uses the share sheet's anchor on iPad; pass the source rect so
  // it doesn't assert. Harmless on phones.
  final box = context.findRenderObject() as RenderBox?;
  await Share.share(
    message,
    subject: 'Join me on Iter',
    sharePositionOrigin:
        box != null ? box.localToGlobal(Offset.zero) & box.size : null,
  );
}

String? _storeLinkForPlatform(AdminConfig config) {
  final ios = config.iosAppStoreUrl.trim();
  final android = config.androidPlayStoreUrl.trim();

  if (kIsWeb) return android.isNotEmpty ? android : ios;

  final isApple = Platform.isIOS || Platform.isMacOS;
  if (isApple) return ios.isNotEmpty ? ios : android;
  return android.isNotEmpty ? android : ios;
}
