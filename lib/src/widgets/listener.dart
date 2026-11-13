import 'package:flutter/widgets.dart';

import '../lifescope.dart';
import '../subscription.dart';

/// Calls lifecycle callbacks while this widget is in the tree.
///
/// The subscription is created when the widget is inserted and cancelled
/// when it is removed, so there is nothing to clean up by hand. The
/// callbacks can change between builds and the latest ones are always used.
///
/// Needs a [LifeScopeProvider] above it. See [LifeScope.listen] for when each
/// callback is called.
///
/// ```dart
/// LifeScopeListener(
///   onHide: player.pause,
///   onShow: player.play,
///   child: const PlayerView(),
/// )
/// ```
class LifeScopeListener extends StatefulWidget {
  /// Creates a widget that listens to lifecycle events.
  const LifeScopeListener({
    super.key,
    this.onResume,
    this.onInactive,
    this.onHide,
    this.onShow,
    this.onPause,
    this.onRestart,
    this.onDetach,
    this.onStateChange,
    required this.child,
  });

  /// See [LifeScope.listen].
  final LifecycleCallback? onResume;

  /// See [LifeScope.listen].
  final LifecycleCallback? onInactive;

  /// See [LifeScope.listen].
  final LifecycleCallback? onHide;

  /// See [LifeScope.listen].
  final LifecycleCallback? onShow;

  /// See [LifeScope.listen].
  final LifecycleCallback? onPause;

  /// See [LifeScope.listen].
  final LifecycleCallback? onRestart;

  /// See [LifeScope.listen].
  final LifecycleCallback? onDetach;

  /// See [LifeScope.listen].
  final LifecycleStateCallback? onStateChange;

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  State<LifeScopeListener> createState() => _LifeScopeListenerState();
}

class _LifeScopeListenerState extends State<LifeScopeListener> {
  LifeScope? _scope;
  LifeScopeSubscription? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = LifeScope.of(context);
    if (scope == _scope) return;
    _subscription?.cancel();
    _scope = scope;
    _subscription = scope.listen(
      onResume: () => widget.onResume?.call(),
      onInactive: () => widget.onInactive?.call(),
      onHide: () => widget.onHide?.call(),
      onShow: () => widget.onShow?.call(),
      onPause: () => widget.onPause?.call(),
      onRestart: () => widget.onRestart?.call(),
      onDetach: () => widget.onDetach?.call(),
      onStateChange: (state) => widget.onStateChange?.call(state),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
