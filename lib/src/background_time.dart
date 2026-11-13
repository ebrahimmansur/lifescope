import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asks iOS for extra background time while async callbacks are running.
///
/// iOS suspends an app a few seconds after it leaves the foreground. While
/// at least one callback passed to [run] is still pending, the native side
/// holds a `UIApplication` background task, which usually extends that to
/// about 30 seconds. It is a no-op on every other platform.
///
/// The native task is shared by the whole process, so the bookkeeping is
/// static. Each keeper only tracks its own share, so one `LifeScope` being
/// disposed never ends the task another one still needs.
class BackgroundTimeKeeper {
  /// Creates a keeper. It does nothing unless [enabled] is true and the app
  /// runs on iOS.
  BackgroundTimeKeeper({required bool enabled, required this.onError})
      : _enabled =
            enabled && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS {
    if (!_enabled) return;
    if (_keepers.isEmpty) _channel.setMethodCallHandler(_handleNativeCall);
    _keepers.add(this);
  }

  /// The channel shared with `LifeScopePlugin.swift`.
  static const MethodChannel _channel =
      MethodChannel('lifescope/background_time');

  static final Set<BackgroundTimeKeeper> _keepers = {};
  static int _pending = 0;
  static bool _active = false;

  /// Called when iOS ends the background time before the work finished.
  final void Function(Object error, StackTrace stack) onError;

  final bool _enabled;
  int _ownPending = 0;
  bool _disposed = false;

  /// Runs [callback]. If it returns a future, background time is held until
  /// that future completes.
  FutureOr<void> run(FutureOr<void> Function() callback) {
    final result = callback();
    if (!_enabled || _disposed || result is! Future<void>) return result;
    _hold();
    return result.whenComplete(_release);
  }

  /// Gives up any background time this keeper still holds.
  void dispose() {
    if (!_enabled || _disposed) return;
    _disposed = true;
    _pending -= _ownPending;
    _ownPending = 0;
    _keepers.remove(this);
    if (_keepers.isEmpty) _channel.setMethodCallHandler(null);
    _endIfIdle();
  }

  void _hold() {
    _ownPending++;
    _pending++;
    if (!_active) {
      _active = true;
      _invoke('begin');
    }
  }

  void _release() {
    if (_disposed) return;
    _ownPending--;
    _pending--;
    _endIfIdle();
  }

  static void _endIfIdle() {
    if (_pending == 0 && _active) {
      _active = false;
      _invoke('end');
    }
  }

  static void _invoke(String method) {
    // A missing plugin (for example in some add-to-app setups) just means
    // no extra time. Lifecycle callbacks still run normally.
    unawaited(
      _channel.invokeMethod<void>(method).then((_) {}, onError: (Object _) {}),
    );
  }

  static Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'expired') return;
    _active = false;
    for (final keeper in List.of(_keepers)) {
      if (keeper._ownPending > 0) {
        keeper.onError(
          TimeoutException(
            'iOS background time ran out before lifecycle callbacks '
            'finished. Keep onHide and onPause work short.',
          ),
          StackTrace.current,
        );
      }
    }
  }
}
