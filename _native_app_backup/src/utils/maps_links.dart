import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_feedback.dart';

/// Opens the device's maps app with directions from the user's current
/// location to ([lat], [lng]).
///
/// Uses the universal Google Maps directions URL — on iOS / Android this opens
/// the installed maps app, otherwise the browser. Free; no API key required.
Future<void> openDirectionsTo(
  BuildContext context, {
  required double lat,
  required double lng,
}) async {
  final dest = '$lat,$lng';
  final dirUri =
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$dest');
  try {
    final ok = await launchUrl(dirUri, mode: LaunchMode.externalApplication);
    if (!ok) {
      await launchUrl(
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$dest'),
        mode: LaunchMode.externalApplication,
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppFeedback.showError(context, 'Could not open maps app');
    }
  }
}
