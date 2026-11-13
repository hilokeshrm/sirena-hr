import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Tapping a notification must open the item it is about, also while the app is in the foreground.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    // iOS only accepts background tasks registered before launching finishes, and only ones listed
    // under BGTaskSchedulerPermittedIdentifiers in Info.plist. Keep this id the same as in phone_alerts_io.dart.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "sirena-check-notifications", earliestBeginInSeconds: 900)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
