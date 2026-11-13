## 0.2.0

- iOS: request extra background time while async onHide/onPause/onDetach
  callbacks are still running (`extendBackgroundTime`, on by default).
- Add `LifeScope.exitRequestsSupported`.
- Document Android and iOS behavior.

## 0.1.0

- First release.
- `LifeScope` with `listen()` for lifecycle callbacks and `state` for the
  current state.
- Exit guards for desktop close requests via `guardExit()`.
- `LifeScopeProvider`, `LifeScopeListener` and `LifeScopeExitGuard` widgets.
