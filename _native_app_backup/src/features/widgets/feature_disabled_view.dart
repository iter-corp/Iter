import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';

/// Shown in place of a feature's UI when the corresponding admin flag is off.
class FeatureDisabledView extends StatelessWidget {
  final String feature;
  final IconData icon;

  const FeatureDisabledView({
    super.key,
    required this.feature,
    this.icon = Icons.block_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: context.textMuted),
              const SizedBox(height: 12),
              Text(
                context.t.featureCurrentlyDisabled(feature),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.t.featureCheckBackLater,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
