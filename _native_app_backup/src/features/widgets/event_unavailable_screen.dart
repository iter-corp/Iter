import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';

class EventUnavailableScreen extends StatelessWidget {
  const EventUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.eventUnavailableTitle),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.event_busy_outlined,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                context.t.eventUnavailableTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.t.eventUnavailableBody,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(context.t.eventUnavailableGoBack),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
