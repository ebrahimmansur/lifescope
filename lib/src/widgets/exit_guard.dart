import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

import '../exit_coordinator.dart';
import '../lifescope.dart';
import '../subscription.dart';

/// Lets [onExitRequested] veto closing the app while this widget is in the
/// tree.
///
/// Useful for screens that hold unsaved work on desktop:
///
/// ```dart
/// LifeScopeExitGuard(
///   onExitRequested: () async {
///     if (!editor.isDirty) return AppExitResponse.exit;
///     final discard = await showDiscardDialog(context);
///     return discard ? AppExitResponse.exit : AppExitResponse.cancel;
///   },
///   child: EditorView(editor: editor),
/// )
/// ```
///
/// Needs a [LifeScopeProvider] above it. See [LifeScope.guardExit] for how
/// guards are combined and when they are asked.
class LifeScopeExitGuard extends StatefulWidget {
  /// Creates a widget that guards exit requests.
  const LifeScopeExitGuard({
    super.key,
    required this.onExitRequested,
    this.timeout,
    this.onTimeout = AppExitResponse.exit,
    required this.child,
  });

  /// Decides whether the app may exit. The latest value is always used.
  final ExitGuardCallback onExitRequested;

  /// See [LifeScope.guardExit]. Read when the guard is registered.
  final Duration? timeout;

  /// See [LifeScope.guardExit]. Read when the guard is registered.
  final AppExitResponse onTimeout;

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  State<LifeScopeExitGuard> createState() => _LifeScopeExitGuardState();
}

class _LifeScopeExitGuardState extends State<LifeScopeExitGuard> {
  LifeScope? _scope;
  LifeScopeSubscription? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = LifeScope.of(context);
    if (scope == _scope) return;
    _scope = scope;
    _register();
  }

  @override
  void didUpdateWidget(LifeScopeExitGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.timeout != oldWidget.timeout ||
        widget.onTimeout != oldWidget.onTimeout) {
      _register();
    }
  }

  void _register() {
    _subscription?.cancel();
    _subscription = _scope!.guardExit(
      () => widget.onExitRequested(),
      timeout: widget.timeout,
      onTimeout: widget.onTimeout,
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
