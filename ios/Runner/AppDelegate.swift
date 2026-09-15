import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()

    // Register for remote notifications (APNs)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { _, _ in }
    }
    application.registerForRemoteNotifications()
    Messaging.messaging().delegate = self

    // Setup keyboard accessory bar hider for WebView
    if let controller = window?.rootViewController as? FlutterViewController {
      let keyboardChannel = FlutterMethodChannel(
        name: "iter/wk_keyboard",
        binaryMessenger: controller.binaryMessenger
      )
      keyboardChannel.setMethodCallHandler { (call, result) in
        if call.method == "hideFormAccessoryBar" {
          // Hides the < > Done bar that appears above keyboard in WKWebView
          self.hideFormAccessoryBar()
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - APNs Token Forwarding
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // MARK: - Hide WKWebView Form Accessory Bar
  private func hideFormAccessoryBar() {
    // Swizzle WKContentView's inputAccessoryView to return nil
    let wkContentViewClass: AnyClass? = NSClassFromString("WKContentView")
    guard let wkClass = wkContentViewClass else { return }

    let originalSelector = #selector(getter: UIResponder.inputAccessoryView)
    let swizzledSelector = #selector(AppDelegate.nilAccessoryView)

    guard let originalMethod = class_getInstanceMethod(wkClass, originalSelector),
          let swizzledMethod = class_getInstanceMethod(AppDelegate.self, swizzledSelector) else { return }

    let newImp = method_getImplementation(swizzledMethod)
    let typeEncoding = method_getTypeEncoding(swizzledMethod)
    class_replaceMethod(wkClass, originalSelector, newImp, typeEncoding)
  }

  @objc func nilAccessoryView() -> UIView? {
    return nil
  }
}

// MARK: - Firebase Messaging Delegate
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    let tokenDict = ["token": fcmToken ?? ""]
    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: tokenDict
    )
  }
}
