import 'package:flutter/widgets.dart';

import '../lifescope.dart';

/// Makes a [LifeScope] available to the widgets below it.
///
/// Widgets find it with `LifeScope.of(context)`.
///
/// Use the default constructor to let the provider create the scope and
/// dispose it when the provider is removed from the tree:
///
/// ```dart
/// runApp(const LifeScopeProvider(child: MyApp()));
/// ```
///
/// Use [LifeScopeProvider.value] when the scope is created somewhere else,
/// for example in `main` so it can also be handed to services. The provider
/// will not dispose a scope it did not create.
///
/// ```dart
/// final lifecycle = LifeScope();
/// final uploads = UploadManager(lifecycle);
/// runApp(LifeScopeProvider.value(scope: lifecycle, child: const MyApp()));
/// ```
class LifeScopeProvider extends StatefulWidget {
  /// Creates a provider that owns its own [LifeScope].
  const LifeScopeProvider({super.key, required this.child}) : scope = null;

  /// Creates a provider for an existing [scope], which it does not own.
  const LifeScopeProvider.value({
    super.key,
    required LifeScope this.scope,
    required this.child,
  });

  /// The scope to provide, or `null` if the provider creates its own.
  final LifeScope? scope;

  /// The widget below this widget in the tree.
  final Widget child;

  /// The nearest [LifeScope] above [context], or `null` if there is none.
  static LifeScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_InheritedLifeScope>()
        ?.scope;
  }

  @override
  State<LifeScopeProvider> createState() => _LifeScopeProviderState();
}

class _LifeScopeProviderState extends State<LifeScopeProvider> {
  LifeScope? _owned;

  LifeScope get _scope => widget.scope ?? (_owned ??= LifeScope());

  @override
  void didUpdateWidget(LifeScopeProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scope != null && _owned != null) {
      _owned!.dispose();
      _owned = null;
    }
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _InheritedLifeScope(scope: _scope, child: widget.child);
  }
}

class _InheritedLifeScope extends InheritedWidget {
  const _InheritedLifeScope({required this.scope, required super.child});

  final LifeScope scope;

  @override
  bool updateShouldNotify(_InheritedLifeScope oldWidget) {
    return scope != oldWidget.scope;
  }
}
