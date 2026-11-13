import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'subscription.dart';

/// Decides whether the application may exit.
///
/// Return [AppExitResponse.cancel] to keep the app open, for example while
/// there are unsaved changes, or [AppExitResponse.exit] to allow it.
typedef ExitGuardCallback = FutureOr<AppExitResponse> Function();

/// Asks the registered guards, one at a time, whether the app may exit.
class ExitCoordinator {
  /// Creates a coordinator that reports guard errors to [onError].
  ExitCoordinator({required this.onError});

  /// Called when a guard throws or times out.
  final void Function(Object error, StackTrace stack) onError;

  final List<_Guard> _guards = [];
  Future<AppExitResponse>? _pending;

  /// Adds a guard. See `LifeScope.guardExit`.
  LifeScopeSubscription add(
    ExitGuardCallback callback, {
    Duration? timeout,
    AppExitResponse onTimeout = AppExitResponse.exit,
  }) {
    late final _Guard guard;
    final subscription = CallbackSubscription(() => _guards.remove(guard));
    guard = _Guard(subscription, callback, timeout, onTimeout);
    _guards.add(guard);
    return subscription;
  }

  /// Resolves an exit request.
  ///
  /// Guards are asked in the order they were added, and the first
  /// [AppExitResponse.cancel] wins. Later guards are not asked, so the user
  /// never sees a second confirmation after cancelling the first one.
  ///
  /// A request that arrives while another one is still being resolved gets
  /// the same answer.
  Future<AppExitResponse> requestExit() {
    return _pending ??= _resolve().whenComplete(() => _pending = null);
  }

  /// Removes every guard.
  void dispose() {
    for (final guard in List.of(_guards)) {
      guard.subscription.cancel();
    }
  }

  Future<AppExitResponse> _resolve() async {
    for (final guard in List.of(_guards)) {
      if (!guard.subscription.isActive) continue;
      final response = await _ask(guard);
      if (response == AppExitResponse.cancel) return AppExitResponse.cancel;
    }
    return AppExitResponse.exit;
  }

  Future<AppExitResponse> _ask(_Guard guard) async {
    try {
      final result = Future.value(guard.callback());
      final timeout = guard.timeout;
      if (timeout == null) return await result;
      return await result.timeout(
        timeout,
        onTimeout: () {
          onError(
            TimeoutException('Exit guard did not answer in time.', timeout),
            StackTrace.current,
          );
          return guard.onTimeout;
        },
      );
    } catch (error, stack) {
      // A broken guard must not trap the user in the app.
      onError(error, stack);
      return AppExitResponse.exit;
    }
  }
}

class _Guard {
  _Guard(this.subscription, this.callback, this.timeout, this.onTimeout);

  final LifeScopeSubscription subscription;
  final ExitGuardCallback callback;
  final Duration? timeout;
  final AppExitResponse onTimeout;
}
