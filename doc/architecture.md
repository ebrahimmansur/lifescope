# Design notes

How lifescope works and why it's built this way. Mostly useful if you want
to contribute, or want to know what happens under the hood.

## Why not just AppLifecycleListener?

`WidgetsBindingObserver` and `AppLifecycleListener` work fine, and for a
small app one listener per feature is enough. They start to hurt when a few
features with async work share the lifecycle:

- Async callbacks aren't awaited. If a save in `onHide` is still running
  when the app comes back, `onShow` runs on top of it.
- `didRequestAppExit` asks every observer even after one already said
  cancel, so two screens with a "discard changes?" dialog will both show it.
- Forgetting `removeObserver` or `dispose` keeps calling into dead objects.

lifescope takes care of delivering events to independent listeners,
ordering and error handling for their callbacks, combining exit guards, and
tying subscriptions to widgets. It doesn't save anything for you, doesn't
know about your state management, and can't do anything once the process
is killed.

## Shape of the API

There's one `LifeScope` object that the app creates and owns. It registers a
single binding observer and hands out subscriptions. Widgets find it through
`LifeScopeProvider`, everything else gets it passed in.

I looked at two other options:

- A `Stream` of events. Familiar, but a stream listener that returns a
  future isn't awaited, so ordering per listener would need to be built on
  top anyway, and errors close the subscription by default. `state` is a
  `ValueListenable` for the simple read-only case instead.
- A global `LifeScope.instance`. Convenient, but it hides the dependency and
  makes tests share state.

Callback names (`onHide`, `onShow`, `onRestart` and so on) and types
(`AppLifecycleState`, `AppExitResponse`) are the same as Flutter's, so
there's nothing new to learn.

## Inside

`lib/src/lifescope.dart` has `LifeScope`, a private observer and one
`_Listener` per `listen()` call.

`lib/src/transitions.dart` fills in skipped states, using the same order as
Flutter: resumed, inactive, hidden, paused, and detached reached from
paused. On a real device the framework already does this before observers
are called, so in practice it only matters when tests call
`handleAppLifecycleStateChanged` directly.

`lib/src/subscription.dart` has `SerialQueue`, which runs one listener's
callbacks in order. A sync callback runs right away, inside the platform
message, which matters on mobile where there's little time after a hide.
An async callback holds the queue until it finishes or `callbackTimeout`
runs out. The callback itself is never cancelled, the queue just stops
waiting.

Events are sent to a copy of the listener list. A listener added during an
event gets the next one, and a cancelled one stops right away.

`lib/src/exit_coordinator.dart` asks guards in the order they were added and
stops at the first cancel. A second exit request while one is still running
gets the same future. If a guard throws, the error is reported and the
answer counts as exit. That's also what Flutter does with a throwing
observer, and it means a bug can't trap the user in the app. Guards have no
default timeout because they often wait on a dialog.

There's no replay of the current state to new listeners. Getting an
`onResume` the moment you subscribe surprises people. `state.value` is
there when you need it.

## iOS background time

iOS suspends an app a few seconds after it leaves the foreground, so a save
started in `onHide` can freeze halfway. `UIApplication.beginBackgroundTask`
gets you more time, usually around 30 seconds. This is the only native code
in the package, a small Swift plugin in `ios/`. Everything else is Dart.

`lib/src/background_time.dart` wraps callbacks for steps into hidden,
paused and detached. Sync callbacks cost nothing. When a callback returns a
future, it counts as pending until it completes. The first pending callback
sends `begin` over the `lifescope/background_time` channel and the last one
to finish sends `end`.

The count is static because the background task belongs to the process, not
to a single `LifeScope`. Each scope also keeps track of its own share, so
disposing one scope can't end a task another one still needs.

If iOS runs out of time anyway, the plugin sends `expired` and scopes with
pending work report a `TimeoutException`. The next callback that needs time
starts a new task. If the plugin is missing (some add-to-app setups),
channel errors are ignored and everything works as before, just without the
extra time.

Android has no equivalent. Long work there belongs in WorkManager or a
foreground service.

## Platform facts this relies on

- `hidden` exists since Flutter 3.13 and is reported on all platforms.
- Exit requests only come on desktop, and only for cancelable exits.
- Android and iOS can kill a backgrounded app with no callback. `detached`
  isn't a reliable "about to die" signal.
- Android can go from detached to paused when the engine starts without a
  visible activity. Flutter gets there through resumed, inactive and hidden,
  so `onResume` fires even though nothing was shown. lifescope keeps that
  behavior instead of second-guessing the framework.
- Permission dialogs, Face ID, Control Center and split-screen focus only
  move between resumed and inactive.

## Tests

- `transitions_test.dart` and `subscription_test.dart` are plain unit tests.
- `lifescope_test.dart` and `exit_guard_test.dart` drive the real binding
  with `handleAppLifecycleStateChanged` and `handleRequestAppExit`.
- `mobile_test.dart` sends messages through the real `flutter/lifecycle`
  channel, the way the Android and iOS embedders do.
- `background_time_test.dart` mocks the native channel and uses
  `TargetPlatformVariant` to run as iOS and Android.
- `test/widgets/` covers mounting, unmounting, rebuilding with new callbacks
  and switching providers.

The exit dialog on desktop is checked by hand with the example app.
