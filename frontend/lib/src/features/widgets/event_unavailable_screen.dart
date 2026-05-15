import 'package:flutter/material.dart';

class EventUnavailableScreen extends StatelessWidget {
  const EventUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event not available'),
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
              const Text(
                'Event not available',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This event was deleted or is no longer available.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
