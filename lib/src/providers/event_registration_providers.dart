import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/event_registration_service.dart';

final eventRegistrationServiceProvider =
    Provider<EventRegistrationService>((_) => EventRegistrationService());


/// Stream of the current user's registration for a specific event.
final myRegistrationProvider = StreamProvider.autoDispose
    .family<EventRegistration?, String>((ref, eventId) {
  return ref.watch(eventRegistrationServiceProvider).streamMine(eventId);
});
