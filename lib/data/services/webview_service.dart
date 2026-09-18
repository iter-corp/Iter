import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../../core/constants/app_constants.dart';
import '../../data/repositories/push_notification_repo.dart';
import '../../data/services/hardware/ble_service.dart';

class WebViewService {
  late final WebViewController controller;
  final VoidCallback? onReady;

  WebViewService({this.onReady});

  WebViewController initialize() {
    late final PlatformWebViewControllerCreationParams params;

    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    controller = WebViewController.fromPlatformCreationParams(params);

    // Fallback: dismiss splash after 1.8s regardless of JS bridge response
    Timer(const Duration(milliseconds: 1800), () {
      onReady?.call();
    });

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_buildUserAgent())
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (progress) {
          debugPrint('[WebView] Progress: $progress%');
          if (progress >= 60) {
            onReady?.call();
          }
        },
        onPageStarted: (url) {
          debugPrint('[WebView] Page started: $url');
          _healCorruptedIndexedDb();
        },
        onPageFinished: (url) {
          debugPrint('[WebView] Page finished: $url');
          _healCorruptedIndexedDb();
          _injectBridgeReadyListener();
          onReady?.call();
        },
        onWebResourceError: (error) {
          debugPrint('[WebView] Error: ${error.description}');
          onReady?.call();
        },
        onNavigationRequest: (request) {
          final url = request.url;

          if (_isAllowedUrl(url)) {
            return NavigationDecision.navigate;
          }
          debugPrint('[WebView] External navigation -> launching in external browser: $url');
          final uri = Uri.tryParse(url);
          if (uri != null) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
      ))
      ..addJavaScriptChannel(
        AppConstants.jsBridgeChannel,
        onMessageReceived: _handleJavaScriptMessage,
      );

    _configureAndroidFileSelector();
    _configureIOSWebView();

    controller.loadRequest(Uri.parse(AppConstants.webAppUrl));

    return controller;
  }

  bool _isAllowedUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    if (uri.scheme == 'about' || uri.scheme == 'data' || uri.scheme == 'javascript') {
      return true;
    }

    final host = uri.host.toLowerCase();
    // Primary app domain
    if (host == 'iterglobal.icu' || host.endsWith('.iterglobal.icu')) {
      return true;
    }

    // Auth & OAuth providers (Firebase Auth handler, Google, Apple)
    if (host.endsWith('firebaseapp.com') ||
        host.endsWith('web.app') ||
        host.endsWith('google.com') ||
        host.endsWith('googleapis.com') ||
        host.endsWith('gstatic.com') ||
        host.endsWith('googleusercontent.com') ||
        host.endsWith('apple.com') ||
        host.endsWith('appleid.apple.com')) {
      return true;
    }

    return false;
  }

  String _buildUserAgent() {
    if (Platform.isIOS) {
      return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
    }
    return 'Mozilla/5.0 (Linux; Android 11; SM-A505F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36';
  }

  void _configureAndroidFileSelector() {
    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;

      androidController.setOnShowFileSelector((params) async {
        try {
          final isImage = params.acceptTypes.any((t) => t.contains('image'));

          if (isImage) {
            final picker = ImagePicker();
            final image = await picker.pickImage(source: ImageSource.gallery);
            if (image != null) {
              return [Uri.file(image.path).toString()];
            }
          } else {
            final res = await FilePicker.platform.pickFiles(
              allowMultiple: params.mode == FileSelectorMode.openMultiple,
            );
            if (res != null) {
              return res.files
                  .where((f) => f.path != null)
                  .map((f) => Uri.file(f.path!).toString())
                  .toList();
            }
          }
        } catch (e) {
          debugPrint('[WebView] File selector error: $e');
        }
        return [];
      });
    }
  }

  void _configureIOSWebView() {
    if (controller.platform is WebKitWebViewController) {
      final webkitController = controller.platform as WebKitWebViewController;
      webkitController.setAllowsBackForwardNavigationGestures(true);
    }
  }

  void _injectBridgeReadyListener() {
    controller.runJavaScript('''
      (function() {
        if (window._iterBridgeInjected) return;
        window._iterBridgeInjected = true;

        // Listen for Flutter Web's first frame
        window.addEventListener('flutter-first-frame', function() {
          if (window.${AppConstants.jsBridgeChannel}) {
            window.${AppConstants.jsBridgeChannel}.postMessage(
              JSON.stringify({ type: '${AppConstants.msgReady}' })
            );
          }
        });

        // MutationObserver fallback
        var observer = new MutationObserver(function(mutations, obs) {
          if (document.querySelector('flutter-view, flt-glass-pane, flt-scene-host, canvas')) {
            if (window.${AppConstants.jsBridgeChannel}) {
              window.${AppConstants.jsBridgeChannel}.postMessage(
                JSON.stringify({ type: '${AppConstants.msgReady}' })
              );
            }
            obs.disconnect();
          }
        });
        observer.observe(document.body || document.documentElement, { childList: true, subtree: true });

        // Safety timeout
        setTimeout(function() {
          if (window.${AppConstants.jsBridgeChannel}) {
            window.${AppConstants.jsBridgeChannel}.postMessage(
              JSON.stringify({ type: '${AppConstants.msgReady}' })
            );
          }
        }, 5000);
      })();
    ''');
  }

  void _handleJavaScriptMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case AppConstants.msgReady:
          debugPrint('[Bridge] Web app READY');
          onReady?.call();
          break;

        case AppConstants.msgAuthLogin:
          final uid = data['uid'] as String?;
          debugPrint('[Bridge] AUTH_LOGIN uid=$uid');
          PushNotificationRepository().registerToken(uid: uid);
          break;

        case AppConstants.msgAuthLogout:
          debugPrint('[Bridge] AUTH_LOGOUT');
          PushNotificationRepository().clearToken();
          break;

        case AppConstants.msgBleScan:
          debugPrint('[Bridge] BLE_SCAN requested');
          _handleBleScan();
          break;

        case AppConstants.msgShare:
          final text = data['text'] as String? ?? '';
          final url = data['url'] as String? ?? '';
          debugPrint('[Bridge] SHARE text=$text url=$url');
          Share.share('$text\n$url');
          break;

        default:
          debugPrint('[Bridge] Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('[Bridge] JS message parse error: $e');
    }
  }

  Future<void> _handleBleScan() async {
    final ble = BleService();
    await ble.startScan(timeout: const Duration(seconds: 8));
    final json = ble.scanResultsToJson();
    controller.runJavaScript('''
      if (window.onIterBleResults) { window.onIterBleResults($json); }
    ''');
  }

  void _healCorruptedIndexedDb() {
    controller.runJavaScript('''
      (function() {
        try {
          var req = indexedDB.open('firebaseLocalStorageDb');
          req.onsuccess = function(e) {
            var db = e.target.result;
            if (db.objectStoreNames.length === 0 || !db.objectStoreNames.contains('firebaseLocalStorage')) {
              console.warn('[WebViewHealer] Corrupted or empty IndexedDB detected. Resetting...');
              db.close();
              var del = indexedDB.deleteDatabase('firebaseLocalStorageDb');
              del.onsuccess = function() {
                console.log('[WebViewHealer] Deleted corrupted database. Reloading clean state...');
                window.location.reload();
              };
            } else {
              db.close();
            }
          };
          req.onerror = function() {
            try {
              indexedDB.deleteDatabase('firebaseLocalStorageDb');
            } catch(e) {}
          };
        } catch (err) {
          console.error('[WebViewHealer] Error checking DB: ' + err);
        }
      })();
    ''');
  }

  Future<void> reload() async {
    await controller.reload();
  }

  Future<bool> canGoBack() async {
    return controller.canGoBack();
  }

  Future<void> goBack() async {
    await controller.goBack();
  }
}
