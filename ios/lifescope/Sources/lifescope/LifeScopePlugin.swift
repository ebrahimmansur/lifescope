import Flutter
import UIKit

/// Keeps the app running in the background while lifescope callbacks finish.
///
/// iOS suspends an app a few seconds after it goes to the background. Dart
/// calls `begin` when an async lifecycle callback starts and `end` when the
/// last one completes, so a checkpoint started in `onHide` gets the extra
/// time iOS allows for finishing work.
public class LifeScopePlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var task: UIBackgroundTaskIdentifier = .invalid

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "lifescope/background_time",
      binaryMessenger: registrar.messenger()
    )
    let instance = LifeScopePlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "begin":
      begin()
      result(nil)
    case "end":
      end()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func begin() {
    guard task == .invalid else { return }
    task = UIApplication.shared.beginBackgroundTask(withName: "lifescope") { [weak self] in
      guard let self = self else { return }
      self.channel.invokeMethod("expired", arguments: nil)
      self.end()
    }
  }

  private func end() {
    guard task != .invalid else { return }
    UIApplication.shared.endBackgroundTask(task)
    task = .invalid
  }
}
