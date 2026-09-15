class AppConstants {
  AppConstants._();

  static const String appName = 'Iter';
  static const String webAppUrl = 'https://iterglobal.icu';
  static const String jsBridgeChannel = 'ITER';

  // JS message types
  static const String msgReady = 'READY';
  static const String msgAuthLogin = 'AUTH_LOGIN';
  static const String msgAuthLogout = 'AUTH_LOGOUT';
  static const String msgBleScan = 'BLE_SCAN';
  static const String msgShare = 'SHARE';

  static const String userAgentSuffix = 'IterNativeApp/2.0';
}
