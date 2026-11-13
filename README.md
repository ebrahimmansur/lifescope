# lifescope

Composable application lifecycle management for Flutter.

Apps usually have several features that care about the lifecycle. A review
session saves progress when the app is hidden, an audio player pauses, an
upload manager stores its queue, and a desktop editor asks before closing
with unsaved changes. `lifescope` lets each feature handle this on its own,
next to the code it belongs to, without one big `WidgetsBindingObserver`
at the root of the app.

- Any number of independent listeners, each with its own subscription.
- Sync or async callbacks. Each listener's callbacks run in order, and a
  slow listener never holds up the others.
- Errors and stuck callbacks are isolated and reported.
- On iOS, extra background time is requested automatically while an
  async `onHide`/`onPause` save is still running.
- Desktop exit requests handled by a list of guards, where the first veto
  wins.
- Widgets that subscribe on mount and clean up on dispose.
- No global singletons and no dependency on any state management package.

## Getting started

```yaml
dependencies:
  lifescope: ^0.1.0
```

Create one `LifeScope` for the app and provide it to the widget tree:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final lifecycle = LifeScope();

  runApp(LifeScopeProvider.value(scope: lifecycle, child: const MyApp()));
}
```

If only widgets need it, `LifeScopeProvider(child: ...)` creates the scope
and disposes it for you.

## Usage

### In a controller or service

Pass the scope in through the constructor and cancel the subscription when
the owner is closed.

```dart
class ReviewSession {
  ReviewSession(LifeScope lifecycle, this._store) {
    _subscription = lifecycle.listen(
      onHide: checkpoint,
      onShow: refresh,
    );
  }

  final ProgressStore _store;
  late final LifeScopeSubscription _subscription;

  Future<void> checkpoint() => _store.save(progress);
  Future<void> refresh() async { /* ... */ }

  void close() => _subscription.cancel();
}
```

This works the same in a Cubit, a Riverpod notifier or a plain class.

### In a widget

```dart
LifeScopeListener(
  onHide: player.pause,
  onShow: player.play,
  child: const PlayerView(),
)
```

The listener lasts as long as the widget. Inside `State` you can also call
`LifeScope.of(context).listen(...)` yourself and cancel it in `dispose`.

To rebuild on the current state, use `lifecycle.state`. It is a
`ValueListenable<AppLifecycleState?>`.

### Guarding exit on desktop

```dart
LifeScopeExitGuard(
  onExitRequested: () async {
    if (!editor.isDirty) return AppExitResponse.exit;
    final discard = await confirmDiscard(context);
    return discard ? AppExitResponse.exit : AppExitResponse.cancel;
  },
  child: EditorView(editor: editor),
)
```

Or, outside of widgets, `lifecycle.guardExit(...)`.

## How callbacks behave

| Callback | Transition |
| --- | --- |
| `onInactive` | resumed → inactive |
| `onHide` | inactive → hidden |
| `onPause` | hidden → paused |
| `onDetach` | paused → detached |
| `onRestart` | paused → hidden |
| `onShow` | hidden → inactive |
| `onResume` | inactive → resumed |
| `onStateChange` | after every step |

- **Skipped states are filled in.** If the platform jumps from `resumed` to
  `paused`, you get `onInactive`, `onHide` and `onPause`.
- **Per-listener ordering.** If `onHide` returns a future, the same
  listener's `onShow` waits for it. To stop one stuck callback from blocking
  forever, the wait is capped by `callbackTimeout` (5 seconds by default).
- **Listeners are independent.** One listener's slow or failing callback
  does not affect another.
- **Errors** go to `FlutterError.reportError`, or to the `onError` you pass
  to `LifeScope`.
- **No replay.** New listeners are not called with the current state. Read
  `lifecycle.state.value` instead.
- **Cancelling is final.** After `cancel()` no callback of that subscription
  runs again. Queued callbacks are dropped.

### Exit guards

- On Android and iOS, also save in `onHide`, because guards are never asked
  there.
- Exit requests are only sent on Windows, macOS and Linux, when the user
  closes the window or the app calls
  `ServicesBinding.instance.exitApplication(AppExitType.cancelable)`.
- Guards are asked one at a time, in the order they were added. The first
  `cancel` keeps the app open and the rest are not asked.
- A guard that throws is reported and counts as `exit`, so a bug can never
  trap the user in the app.
- `timeout` and `onTimeout` can be set per guard. There is no default timeout,
  because a guard may be waiting for a dialog.

## Platform behavior

Lifecycle callbacks are best effort everywhere. Being hidden is not the
same as being terminated, and a force quit or a crash calls nothing. Save
important state in `onHide` and keep that work short.

### Android

- **Process death.** Once the app is in the background, Android can kill
  the process at any time with no further callback. `onDetach` is not a
  reliable "about to die" signal.
- **Coming back after process death** is a cold start, not `onShow`. Restore
  state at startup, or use Flutter's `RestorationMixin`.
- **Back button on the root route** finishes the activity. You get
  `onInactive`, `onHide`, `onPause` and `onDetach`. To stop it, use
  `PopScope`. Exit guards do not run on Android.
- **Permission dialogs and multi-window.** A system dialog or losing focus
  in split screen only makes the app inactive. Picture-in-picture is also
  visible but inactive. None of these call `onHide`.
- **Starting in the background.** When the engine starts without a visible
  activity, for example for a push message, Flutter reports `resumed`,
  `inactive`, `hidden`, `paused` in quick succession. This is Flutter's own
  behavior and lifescope passes it on unchanged.

### iOS

- **Background time.** iOS suspends an app a few seconds after it leaves the
  foreground. While an async `onHide`, `onPause` or `onDetach` callback is
  still running, lifescope holds a `UIApplication` background task, which
  usually extends this to about 30 seconds. When iOS ends the time early, a
  `TimeoutException` is reported through `onError`. Turn this off with
  `LifeScope(extendBackgroundTime: false)`.
- **Short interruptions** like Control Center, Notification Center, an
  incoming call banner, Face ID or the app switcher only make the app
  inactive. Use `onHide`/`onShow` for "the user left", not `onInactive`.
- **No exit requests.** iOS apps are never asked before closing. Swiping the
  app away from the switcher kills it with no callback.

### Desktop

- Hiding or minimizing the window gives `onHide`. Closing it sends an exit
  request to your guards first (see above).

### Web

- `onHide`/`onShow` follow page visibility. Closing the tab gives no chance
  to run async work, and exit guards do not run.

Use `LifeScope.exitRequestsSupported` to check whether guards will ever be
asked on the current platform.

## Testing

`LifeScope` uses the normal `WidgetsBinding`, so you can drive it from widget
tests:

```dart
tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
final response = await tester.binding.handleRequestAppExit();
```

See [doc/architecture.md](doc/architecture.md) for the design and the
reasoning behind it.
