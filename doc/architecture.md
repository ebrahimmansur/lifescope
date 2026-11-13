# Architecture

Notes on how lifescope is put together and why. Written for contributors and
for anyone deciding whether the package fits their app.

## The problem

Many features depend on the same app lifecycle but have nothing else in
common. A review session wants to checkpoint on hide. An upload manager
wants to save its queue. A player wants to pause. A desktop editor wants to
stop the window from closing while there is unsaved work.

Flutter offers `WidgetsBindingObserver` and `AppLifecycleListener`. Both work,
but leave a few things to every app:

- Async callbacks are fire-and-forget. If a checkpoint is still running
  when the app comes back, the refresh can run on top of it.
- An exception in one observer is reported, but there is no policy for what
  it means, for example for an exit decision.
- `didRequestAppExit` asks every observer, even after one has said cancel.
  Two screens with "discard changes?" dialogs will both show one.
- Ownership is manual. Forgetting `removeObserver` or `dispose` leaks the
  observer and keeps calling into dead objects.

## What lifescope owns, and what it does not

Owns:

- Delivering lifecycle transitions to any number of independent listeners.
- Ordering, error isolation and timeouts for those callbacks.
- Combining exit guards into one answer.
- Tying subscriptions to widget lifetimes.

Leaves to the app:

- What to save and where. There is no persistence layer.
- State management. Listeners are plain callbacks.
- Anything after the process is killed. That cannot be observed.

## Options considered

**One `AppLifecycleListener` per feature.** This is the simplest choice and
it needs no package. It has the problems listed above, and it is awkward to
test non-widget classes with it. It is fine for small apps.

**An event stream (`Stream<LifecycleEvent>`).** It is familiar, but streams
fit badly with async work. A `listen` callback that returns a future is not
awaited, so per-listener ordering would have to be built on top anyway.
Error handling also becomes stream errors, which close subscriptions by
default. It is rejected as the main API. `state` is exposed as a
`ValueListenable` for the read-only case.

**A global singleton (`LifeScope.instance`).** It is convenient, but it
hides the dependency, makes tests share state, and is something the package
explicitly wants to avoid.

**A central coordinator object, passed around like any other dependency.**
This is what lifescope uses. There is one owned `LifeScope`, created by the
app, which registers one binding observer and hands out subscriptions.
Widgets find it through an `InheritedWidget`. Everything else gets it
through its constructor.

## Components

```
LifeScope ─── one WidgetsBindingObserver (private _Observer)
 │
 ├── listeners: [_Listener]   each has callbacks + SerialQueue
 │      └── LifeScopeSubscription (cancel)
 │
 ├── ExitCoordinator          ordered guards, first cancel wins
 │      └── LifeScopeSubscription (cancel)
 │
 └── state: ValueListenable<AppLifecycleState?>

LifeScopeProvider   InheritedWidget, owns or borrows a LifeScope
LifeScopeListener   widget, subscribes while mounted
LifeScopeExitGuard  widget, guards exit while mounted
```

- `expandTransition` (`lib/src/transitions.dart`) is a pure function that
  fills in skipped states. It follows the same model as
  `AppLifecycleListener`: resumed ↔ inactive ↔ hidden ↔ paused, with
  detached reached from paused and left to resumed.
- `SerialQueue` (`lib/src/subscription.dart`) runs one listener's callbacks
  in order. A synchronous callback runs immediately, inside the platform
  message. That matters on mobile, where there is little time after a hide.
  An async callback holds the queue until it completes or `callbackTimeout`
  passes.
- `ExitCoordinator` (`lib/src/exit_coordinator.dart`) asks guards in
  registration order. A request that arrives while one is in progress gets
  the same future.

## Key decisions

| Decision | Why |
| --- | --- |
| Listeners run independently | One feature's slow save should not delay another's. |
| Callbacks of one listener run in order | `onShow` should not run before the same listener's `onHide` finished. |
| Timeout on that ordering (5 s default) | A hung future must not block a listener forever. The callback itself is not cancelled. |
| Dispatch works on a snapshot | Listeners added during an event wait for the next one. Cancelled ones stop at once. |
| No replay of the current state | Replaying on subscribe surprises people (an `onResume` on first build). `state.value` is explicit. |
| Exit guards are separate from listeners | A guard returns a vote and may wait for the user. Notifications do neither. |
| First cancel wins, later guards skipped | Avoids stacked confirmation dialogs. |
| Throwing guard means exit | A bug must never make the app impossible to close. This matches Flutter's own handling of throwing observers. |
| No default guard timeout | Guards often show dialogs. |
| `AppExitResponse` and `AppLifecycleState` reused | No new vocabulary for people who already know Flutter. |

## Platform notes

Confirmed Flutter behaviour:

- `hidden` exists since Flutter 3.13. All platforms report it, synthesized
  where the OS has no equivalent.
- Exit requests (`didRequestAppExit`) only come on desktop, and only for
  cancelable exits. Mobile and web never send them.
- Android and iOS can kill a paused (or hidden) app without further
  callbacks. `detached` is not a reliable "about to die" signal.
- On web, `hidden`/`paused` follow page visibility. Closing the tab gives no
  chance to run async work.
- On Android and iOS the embedder sends single states over
  `flutter/lifecycle`. `ServicesBinding._generateStateTransitions` fills in
  the steps in between before any observer is called. So in production,
  `expandTransition` only ever sees single steps. It matters when
  `handleAppLifecycleStateChanged` is called directly, as tests do.
- `detached → paused` is a valid platform transition on Android, when the
  engine starts with no visible activity. Flutter still walks
  `resumed → inactive → hidden → paused` to get there, so `onResume` fires
  even though nothing was shown. lifescope matches this rather than
  second-guessing the framework.
- Short interruptions (permission dialogs, Face ID, Control Center,
  split-screen focus) only move between `resumed` and `inactive`.

lifescope does not change any of this. It only organises who gets told.
The one exception is iOS background time, below.

## iOS background time

iOS suspends an app a few seconds after it leaves the foreground. An async
checkpoint in `onHide` can freeze halfway and only finish when the user
comes back, if at all. `UIApplication.beginBackgroundTask` asks for more
time, usually about 30 seconds.

This is the only native code in the package (`ios/`, a Swift plugin of
about 50 lines). Every other platform stays pure Dart.

- `BackgroundTimeKeeper` (`lib/src/background_time.dart`) wraps callbacks
  for steps into `hidden`, `paused` and `detached`. A sync callback costs
  nothing. When a callback returns a future, the keeper counts it as
  pending until it completes.
- The first pending callback sends `begin` over
  `lifescope/background_time`, and the last one to finish sends `end`. The
  count is static, because the background task belongs to the process and
  not to one `LifeScope`. Each keeper also tracks its own share, so
  disposing one scope cannot end a task another one still needs.
- The hold lasts until the real future completes, not until
  `callbackTimeout`. The timeout only decides when the same listener's next
  callback may start.
- If iOS ends the time early, the plugin sends `expired`. Keepers with
  pending work report a `TimeoutException`. The next callback that needs
  time starts a new task.
- Channel errors such as `MissingPluginException` are ignored. With no
  plugin the package behaves exactly as before, just without extra time.

Android has no equivalent API. Long work there belongs in WorkManager or a
foreground service, which is outside this package's scope.

## Testing strategy

- Mobile scenarios sent through the real `flutter/lifecycle` channel:
  interruptions, home screen and back, the back button, background engine
  start, and cold start.
- Background time tested against a mocked channel with
  `TargetPlatformVariant`, covering iOS only, sync and async callbacks,
  overlap, expiry, a missing plugin, and several scopes.
- Unit tests for `expandTransition` and `SerialQueue`, covering ordering,
  re-entrancy, errors and closing.
- Widget tests that drive the real binding with
  `handleAppLifecycleStateChanged` and `handleRequestAppExit`, covering
  dispatch order, isolation, timeouts, cancellation during dispatch, guard
  ordering, coalescing and failure policy.
- Widget tests for the provider, listener and guard widgets, covering
  mount, unmount, rebuild with new callbacks, and provider swaps.
- Manual desktop check with the example app: close the window with
  "Unsaved changes" on.

## Possible later work

- A `package:lifescope/testing.dart` helper, if driving the binding turns
  out to be awkward in pure unit tests.
- An integration test target for the example on desktop CI.
