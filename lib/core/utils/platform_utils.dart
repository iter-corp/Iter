import 'dart:io' show Platform;

class PlatformUtils {
  PlatformUtils._();

  static bool get isIOS => Platform.isIOS;
  static bool get isAndroid => Platform.isAndroid;
}
