## 0.1.0

First release.

- `LifeScope` with `listen()` for lifecycle callbacks and `state` for the
  current state.
- `guardExit()` to let features veto closing the app on desktop.
- `LifeScopeProvider`, `LifeScopeListener` and `LifeScopeExitGuard` widgets.
- On iOS, extra background time is requested while async `onHide`,
  `onPause` or `onDetach` callbacks are still running.
