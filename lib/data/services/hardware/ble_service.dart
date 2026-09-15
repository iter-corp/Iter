import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static final BleService _instance = BleService._();
  factory BleService() => _instance;
  BleService._();

  final List<ScanResult> _scanResults = [];
  StreamSubscription? _scanSub;
  bool _isScanning = false;

  bool get isScanning => _isScanning;
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);

  Future<bool> get isAvailable async {
    try {
      return await FlutterBluePlus.isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) return;

    final supported = await isAvailable;
    if (!supported) {
      debugPrint('[BLE] Bluetooth not supported on this device');
      return;
    }

    _isScanning = true;
    _scanResults.clear();

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final idx = _scanResults.indexWhere(
          (existing) => existing.device.remoteId == r.device.remoteId,
        );
        if (idx >= 0) {
          _scanResults[idx] = r;
        } else {
          _scanResults.add(r);
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      debugPrint('[BLE] Scan error: $e');
    }

    _isScanning = false;
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _isScanning = false;
  }

  String scanResultsToJson() {
    return jsonEncode(_scanResults.map((r) => {
      'id': r.device.remoteId.str,
      'name': r.device.platformName,
      'rssi': r.rssi,
    }).toList());
  }
}
