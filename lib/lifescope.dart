/// Composable application lifecycle management for Flutter.
library;

export 'dart:ui' show AppExitResponse;

export 'src/exit_coordinator.dart' show ExitGuardCallback;
export 'src/lifescope.dart'
    show
        LifeScope,
        LifeScopeErrorHandler,
        LifecycleCallback,
        LifecycleStateCallback;
export 'src/subscription.dart' show LifeScopeSubscription;
export 'src/widgets/provider.dart' show LifeScopeProvider;
