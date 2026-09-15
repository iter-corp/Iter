import 'package:flutter/material.dart';

import '../features/screens/user_screen.dart';

/// Navigates to the user profile screen for the given [uid].
Future<T?> openUserProfile<T>(BuildContext context, {required String uid}) {
  return Navigator.push<T>(
    context,
    MaterialPageRoute(
      builder: (_) => UserProfileScreen(uid: uid),
    ),
  );
}
