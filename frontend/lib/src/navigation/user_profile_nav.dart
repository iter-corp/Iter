import 'package:flutter/material.dart';

import '../features/screens/user_screen.dart';

/// Navigates to the user profile screen for the given [uid].
void openUserProfile(BuildContext context, {required String uid}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => UserProfileScreen(uid: uid),
    ),
  );
}
