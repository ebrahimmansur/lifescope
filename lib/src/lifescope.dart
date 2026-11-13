import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'exit_coordinator.dart';
import 'subscription.dart';
import 'transitions.dart';
import 'widgets/provider.dart';

/// A callback for a lifecycle event. May be synchronous or asynchronous.
typedef LifecycleCallback = FutureOr<void> Function();

/// A callback that receives the new [AppLifecycleState].
typedef LifecycleStateCallback = FutureOr<void> Function(
  AppLifecycleState state,
);

/// Receives errors thrown by lifecycle callbacks and exit guards.
typedef LifeScopeErrorHandler = void Function(Object error, StackTrace stack);

/// Coordinates application lifecycle callbacks for any number of
/// independent listeners.
///
/// Create one `LifeScope` for the application, usually in `main`, and pass
/// it to the parts of the app that need it. A `LifeScope` registers a single
/// observer with [WidgetsBinding], so [WidgetsFlutterBinding.ensureInitialized]
/// must be called first. Call [dispose] when it is no longer needed.
///
/// Each listener added with [listen] is isolated from the others:
///
///  * callbacks of different listeners run independently, so a slow
///    callback in one feature never delays another;
///  * callbacks of the same listener run in order, so an async `onHide`
///    finishes before that listener's `onShow` starts;
///  * an error in one callback is reported and does not affect anything
///    else.
///
/// Lifecycle callbacks are best effort. The operating system may suspend or
/// kill the process at any time after the app is hidden, so there is no
/// guarantee that asynchronous work started in a callback will complete.
class LifeScope {
  /// Creates a scope and starts observing the application lifecycle.
  ///
  /// [callbackTimeout] limits how long a listener's async callback can hold
  /// back that listener's next callback. When it runs out, a
  /// [TimeoutException] is reported and the next callback runs anyway.
  ///
  /// Errors thrown by callbacks go to [onError]. By default they are
  /// reported with [FlutterError.reportError].
  LifeScope({
    this.callbackTimeout = const Duration(seconds: 5),
    LifeScopeErrorHandler? onError,
  })  : _binding = WidgetsBinding.instance,
        _onError = onError {
    _state = ValueNotifier<AppLifecycleState?>(_binding.lifecycleState);
    _observer = _Observer(this);
    _binding.addObserver(_observer);
  }

  /// The [LifeScope] from the closest [LifeScopeProvider] above [context].
  ///
  /// Throws if there is no provider. Use [maybeOf] to get `null` instead.
  static LifeScope of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw FlutterError.fromParts([
        ErrorSummary('LifeScope.of() called with no LifeScopeProvider above.'),
        ErrorHint(
          'Wrap your app in a LifeScopeProvider, for example '
          'runApp(LifeScopeProvider(child: MyApp())).',
        ),
        context.describeElement('The context used was'),
      ]);
    }
    return scope;
  }

  /// The [LifeScope] from the closest [LifeScopeProvider] above [context],
  /// or `null` if there is none.
  static LifeScope? maybeOf(BuildContext context) {
    return LifeScopeProvider.maybeOf(context);
  }

  /// Whether the current platform sends exit requests to [guardExit].
  ///
  /// True on Windows, macOS and Linux. False on Android, iOS and the web,
  /// where the OS closes apps without asking. There, save work in `onHide`
  /// instead, and use `PopScope` to handle the Android back button.
  static bool get exitRequestsSupported {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux =>
        true,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia =>
        false,
    };
  }

  /// How long an async callback may delay the next callback of the same
  /// listener. `null` waits forever.
  final Duration? callbackTimeout;

  final WidgetsBinding _binding;
  final LifeScopeErrorHandler? _onError;
  late final _Observer _observer;
  late final ValueNotifier<AppLifecycleState?> _state;
  final List<_Listener> _listeners = [];
  late final ExitCoordinator _exit =
      ExitCoordinator(onError: _reportCallbackError);
  bool _disposed = false;

  /// The current lifecycle state, or `null` if the platform has not
  /// reported one yet.
  ///
  /// The current state is not replayed to new listeners. Read
  /// `state.value` to find out where the app is right now.
  ValueListenable<AppLifecycleState?> get state => _state;

  /// Adds a listener for lifecycle events and returns its subscription.
  ///
  /// The callbacks follow the transitions of [AppLifecycleState]:
  ///
  ///  * [onInactive]: `resumed` to `inactive`.
  ///  * [onHide]: `inactive` to `hidden`.
  ///  * [onPause]: `hidden` to `paused`.
  ///  * [onDetach]: `paused` to `detached`.
  ///  * [onRestart]: `paused` to `hidden`.
  ///  * [onShow]: `hidden` to `inactive`.
  ///  * [onResume]: `inactive` (or `detached`) to `resumed`.
  ///
  /// When the platform skips states, the missing steps are filled in, so a
  /// jump from `resumed` to `paused` calls [onInactive], [onHide] and
  /// [onPause] in that order. [onStateChange] is called after each step.
  ///
  /// Call [LifeScopeSubscription.cancel] when the owner is disposed.
  LifeScopeSubscription listen({
    LifecycleCallback? onResume,
    LifecycleCallback? onInactive,
    LifecycleCallback? onHide,
    LifecycleCallback? onShow,
    LifecycleCallback? onPause,
    LifecycleCallback? onRestart,
    LifecycleCallback? onDetach,
    LifecycleStateCallback? onStateChange,
  }) {
    _checkNotDisposed();
    late final _Listener listener;
    final subscription = CallbackSubscription(() {
      listener.queue.close();
      _listeners.remove(listener);
    });
    listener = _Listener(
      subscription: subscription,
      queue: SerialQueue(
        onError: _reportCallbackError,
        timeout: callbackTimeout,
      ),
      onResume: onResume,
      onInactive: onInactive,
      onHide: onHide,
      onShow: onShow,
      onPause: onPause,
      onRestart: onRestart,
      onDetach: onDetach,
      onStateChange: onStateChange,
    );
    _listeners.add(listener);
    return subscription;
  }

  /// Lets [onExitRequested] veto a request to close the application.
  ///
  /// Exit requests come from the platform when the user tries to close a
  /// desktop app (Windows, macOS and Linux), or from
  /// `ServicesBinding.instance.exitApplication(AppExitType.cancelable)`.
  /// Mobile and web platforms do not send them (see [exitRequestsSupported]).
  /// They are not sent when the process is killed either.
  ///
  /// Guards are asked one at a time, in the order they were added. The
  /// first guard to return [AppExitResponse.cancel] keeps the app open and
  /// the remaining guards are not asked. This lets a guard show a
  /// confirmation dialog without another dialog popping up after it.
  ///
  /// A guard that throws is reported and counts as
  /// [AppExitResponse.exit], so a bug can never stop the user from closing
  /// the app. If [timeout] is set and the guard has not answered in time,
  /// [onTimeout] is used instead. There is no timeout by default because a
  /// guard may be waiting for the user to answer a dialog.
  ///
  /// Call [LifeScopeSubscription.cancel] to remove the guard.
  LifeScopeSubscription guardExit(
    ExitGuardCallback onExitRequested, {
    Duration? timeout,
    AppExitResponse onTimeout = AppExitResponse.exit,
  }) {
    _checkNotDisposed();
    return _exit.add(onExitRequested, timeout: timeout, onTimeout: onTimeout);
  }

  /// Stops observing the lifecycle and cancels every subscription.
  ///
  /// The scope cannot be used after this.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _binding.removeObserver(_observer);
    _exit.dispose();
    for (final listener in List.of(_listeners)) {
      listener.subscription.cancel();
    }
    _state.dispose();
  }

  void _handleStateChange(AppLifecycleState next) {
    final previous = _state.value;
    final steps = expandTransition(previous, next);
    if (steps.isEmpty) return;
    _state.value = next;

    // Listeners added or removed by a callback do not affect this dispatch.
    final listeners = List.of(_listeners);
    var from = previous;
    for (final to in steps) {
      for (final listener in listeners) {
        listener.dispatch(from, to);
      }
      from = to;
    }
  }

  void _reportCallbackError(Object error, StackTrace stack) {
    final onError = _onError;
    if (onError != null) {
      onError(error, stack);
      return;
    }
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'lifescope',
      context: ErrorDescription('while running a lifecycle callback'),
    ));
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('This LifeScope has been disposed.');
    }
  }
}

class _Observer with WidgetsBindingObserver {
  _Observer(this._scope);

  final LifeScope _scope;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _scope._handleStateChange(state);
  }

  @override
  Future<AppExitResponse> didRequestAppExit() => _scope._exit.requestExit();
}

class _Listener {
  _Listener({
    required this.subscription,
    required this.queue,
    this.onResume,
    this.onInactive,
    this.onHide,
    this.onShow,
    this.onPause,
    this.onRestart,
    this.onDetach,
    this.onStateChange,
  });

  final LifeScopeSubscription subscription;
  final SerialQueue queue;
  final LifecycleCallback? onResume;
  final LifecycleCallback? onInactive;
  final LifecycleCallback? onHide;
  final LifecycleCallback? onShow;
  final LifecycleCallback? onPause;
  final LifecycleCallback? onRestart;
  final LifecycleCallback? onDetach;
  final LifecycleStateCallback? onStateChange;

  void dispatch(AppLifecycleState? from, AppLifecycleState to) {
    if (!subscription.isActive) return;
    final callback = _callbackFor(from, to);
    if (callback != null) queue.add(callback);
    final onStateChange = this.onStateChange;
    if (onStateChange != null) queue.add(() => onStateChange(to));
  }

  LifecycleCallback? _callbackFor(
    AppLifecycleState? from,
    AppLifecycleState to,
  ) {
    switch (to) {
      case AppLifecycleState.resumed:
        return onResume;
      case AppLifecycleState.inactive:
        return from == AppLifecycleState.hidden ? onShow : onInactive;
      case AppLifecycleState.hidden:
        return from == AppLifecycleState.paused ? onRestart : onHide;
      case AppLifecycleState.paused:
        return onPause;
      case AppLifecycleState.detached:
        return onDetach;
    }
  }
}
