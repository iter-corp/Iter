import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

class WifiDiscoveryService {
  static final WifiDiscoveryService _instance = WifiDiscoveryService._();
  factory WifiDiscoveryService() => _instance;
  WifiDiscoveryService._();

  final NetworkInfo _networkInfo = NetworkInfo();

  Future<Map<String, String?>> getWifiInfo() async {
    try {
      final wifiName = await _networkInfo.getWifiName();
      final wifiBSSID = await _networkInfo.getWifiBSSID();
      final wifiIP = await _networkInfo.getWifiIP();
      final wifiGateway = await _networkInfo.getWifiGatewayIP();
      final wifiSubmask = await _networkInfo.getWifiSubmask();

      debugPrint('[WiFi] SSID=$wifiName IP=$wifiIP');

      return {
        'ssid': wifiName,
        'bssid': wifiBSSID,
        'ip': wifiIP,
        'gateway': wifiGateway,
        'submask': wifiSubmask,
      };
    } catch (e) {
      debugPrint('[WiFi] getWifiInfo error: $e');
      return {};
    }
  }
}
