import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 背景檢查提醒／私訊用的任務代號。
  /// 三個地方必須完全一致，改一個就要三個都改：
  ///   1. 這裡（註冊處理常式）
  ///   2. Info.plist 的 BGTaskSchedulerPermittedIdentifiers
  ///   3. Dart 的 backgroundTaskName（lib/services/background.dart）
  private static let badgeTaskIdentifier = "gm.badges"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // iOS 規定 BGTaskScheduler 的每個任務代號都要在 App **啟動完成之前**
    // 註冊好處理常式。少了這行，Dart 那邊一呼叫 registerPeriodicTask 就會
    // 丟「No launch handler registered for task with identifier gm.badges」
    // 例外——使用者登入後會直接看到一個崩潰對話框，而且背景檢查從頭到尾
    // 都沒有真的排上。
    //
    // 這裡只註冊處理常式；真正的排程仍由 Dart 端的 Workmanager 發起。
    // earliestBeginInSeconds 收的是 NSNumber?，Int 不會自動轉
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: Self.badgeTaskIdentifier,
      earliestBeginInSeconds: NSNumber(value: 15 * 60)
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
