import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<void> requestStartupPermissions() async {
    final permissions = <Permission>[
      Permission.camera,
      Permission.location,
      Permission.notification,
    ];

    if (Platform.isAndroid) {
      permissions.add(Permission.bluetoothScan);
      permissions.add(Permission.bluetoothConnect);
    } else if (Platform.isIOS) {
      permissions.add(Permission.bluetooth);
    }

    final statuses = await permissions.request();
    for (final entry in statuses.entries) {
      debugPrint('[Permissions] ${entry.key}: ${entry.value}');
    }
  }
}
