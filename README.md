# lifescope

App lifecycle handling for Flutter, split up by feature.

In most apps a few unrelated things care about the lifecycle. A study
session saves progress when the app goes to the background, a player
pauses, an upload queue gets written to disk, and on desktop an editor
wants to ask before the window closes. Usually all of that ends up in one
`WidgetsBindingObserver` near the root of the app. With lifescope each
feature subscribes on its own and cleans up after itself.

What you get:

- As many independent listeners as you need. Each one gets a subscription
  you can cancel.
- Callbacks can be sync or async. A listener's callbacks run in order, and
  a slow listener doesn't hold up the others.
- Exceptions and stuck callbacks are caught and reported, they don't break
  other listeners.
- On iOS the app asks for extra background time while an async save in
  `onHide` or `onPause` is still running.
- Exit guards for desktop: several screens can veto closing the window,
  and the first one that says no wins.
- Widgets that subscribe when mounted and unsubscribe when disposed.
- No singletons, and nothing tied to a state management package.

## Install

```yaml
dependencies:
  lifescope: ^0.1.0
```

## Setup

Create one `LifeScope` and put it above your app:

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

### Controllers and services

Pass the scope in through the constructor and cancel the subscription when
you close the object:

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

Works the same way in a Cubit, a Riverpod notifier or a plain class.

### Widgets

```dart
LifeScopeListener(
  onHide: player.pause,
  onShow: player.play,
  child: const PlayerView(),
)
```

The subscription lives as long as the widget. You can also call
`LifeScope.of(context).listen(...)` in a `State` and cancel it in `dispose`.

`lifecycle.state` is a `ValueListenable<AppLifecycleState?>` if you want to
rebuild on the current state.

### Asking before the window closes (desktop)

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

Outside of widgets use `lifecycle.guardExit(...)`.

## Callbacks

| Callback | Called when the app goes from |
| --- | --- |
| `onInactive` | resumed to inactive |
| `onHide` | inactive to hidden |
| `onPause` | hidden to paused |
| `onDetach` | paused to detached |
| `onRestart` | paused to hidden |
| `onShow` | hidden to inactive |
| `onResume` | inactive to resumed |
| `onStateChange` | any state to the next one |

A few things to know:

- If the platform skips states, for example resumed straight to paused, the
  missing steps are filled in, so you still get `onInactive`, `onHide` and
  `onPause`.
- If `onHide` returns a future, the same listener's `onShow` waits for it.
  The wait is capped by `callbackTimeout` (5 seconds by default) so one
  stuck future can't block the listener forever.
- Errors go to `FlutterError.reportError`, or to `onError` if you pass one
  to `LifeScope`.
- A new listener isn't called with the current state. Read
  `lifecycle.state.value` if you need it.
- After `cancel()` nothing from that subscription runs again, queued
  callbacks included.

### Exit guards

- Only Windows, macOS and Linux send exit requests, when the user closes the
  window or the app calls
  `ServicesBinding.instance.exitApplication(AppExitType.cancelable)`.
  Android, iOS and web never do, so save in `onHide` there too.
  `LifeScope.exitRequestsSupported` tells you which case you're in.
- Guards are asked one at a time in the order they were added. The first
  one to return `cancel` keeps the app open and the rest aren't asked.
- If a guard throws, the error is reported and the app is allowed to close.
  A bug in a guard should never make the app impossible to quit.
- You can give a guard a `timeout` and an `onTimeout` answer. There's no
  default timeout since a guard might be waiting on a dialog.

## Platform notes

Lifecycle callbacks are best effort on every platform. Hidden doesn't mean
terminated, and a force quit or crash calls nothing. Save what matters in
`onHide` and keep that work short.

### Android

- Once the app is in the background Android can kill the process without
  any further callback. Don't count on `onDetach`.
- Coming back after the process was killed is a cold start, not `onShow`.
  Restore state at startup or with `RestorationMixin`.
- Pressing back on the root route finishes the activity, and you get
  `onInactive`, `onHide`, `onPause` and `onDetach`. Use `PopScope` if you
  want to stop it.
- Permission dialogs, losing focus in split screen and picture-in-picture
  only make the app inactive. `onHide` isn't called for these.
- If the engine starts without a visible activity (a push message, for
  example), Flutter reports resumed, inactive, hidden and paused in a row.
  That's how Flutter itself behaves and lifescope passes it through as is.

### iOS

- iOS suspends an app a few seconds after it leaves the foreground. While
  an async `onHide`, `onPause` or `onDetach` callback is still running,
  lifescope holds a background task, which usually gives you around 30
  seconds. If iOS still runs out of time, a `TimeoutException` is reported.
  Turn this off with `LifeScope(extendBackgroundTime: false)`.
- Control Center, Notification Center, an incoming call banner, Face ID and
  the app switcher only make the app inactive. Use `onHide` and `onShow`
  when you mean "the user left", not `onInactive`.
- iOS never asks before closing an app. Swiping it away kills it with no
  callback.

### Desktop

Minimizing or hiding the window calls `onHide`. Closing it asks your exit
guards first.

### Web

`onHide` and `onShow` follow page visibility. Closing the tab doesn't give
async work a chance to run, and exit guards aren't called.

## Testing

`LifeScope` uses the regular `WidgetsBinding`, so widget tests can drive it
directly:

```dart
tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
final response = await tester.binding.handleRequestAppExit();
```

Design notes are in [doc/architecture.md](https://github.com/ebrahimmansur/lifescope/blob/main/doc/architecture.md).
