import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo above the wordmark — matches the launcher icon so the
            // splash reads as a true brand surface instead of plain text.
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/img/app_icon.png',
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/icons/app_icon.png',
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.t.splashAppName,
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 28),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
