import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifescope/lifescope.dart';

/// Sends a lifecycle message the way the Android and iOS embedders do, so the
/// framework's own transition handling runs before LifeScope sees it.
Future<void> sendPlatformState(
  WidgetTester tester,
  AppLifecycleState state,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
    (_) {},
  );
}

void main() {
  late LifeScope scope;
  late List<String> log;

  LifeScopeSubscription listenAll() {
    return scope.listen(
      onResume: () => log.add('resume'),
      onInactive: () => log.add('inactive'),
      onHide: () => log.add('hide'),
      onShow: () => log.add('show'),
      onPause: () => log.add('pause'),
      onRestart: () => log.add('restart'),
      onDetach: () => log.add('detach'),
    );
  }

  void start(WidgetTester tester, AppLifecycleState? initial) {
    log = [];
    tester.binding.resetInternalState();
    if (initial != null) tester.binding.handleAppLifecycleStateChanged(initial);
    scope = LifeScope();
    addTearDown(scope.dispose);
    listenAll();
  }

  testWidgets(
      'short interruptions (permission dialog, Face ID, control center) '
      'do not count as hiding the app', (tester) async {
    start(tester, AppLifecycleState.resumed);

    await sendPlatformState(tester, AppLifecycleState.inactive);
    await sendPlatformState(tester, AppLifecycleState.resumed);

    expect(log, ['inactive', 'resume']);
  });

  testWidgets('going to the home screen and back', (tester) async {
    start(tester, AppLifecycleState.resumed);

    await sendPlatformState(tester, AppLifecycleState.paused);
    await sendPlatformState(tester, AppLifecycleState.resumed);

    expect(log, [
      'inactive', 'hide', 'pause', //
      'restart', 'show', 'resume',
    ]);
  });

  testWidgets('Android back button closing the activity', (tester) async {
    start(tester, AppLifecycleState.resumed);

    await sendPlatformState(tester, AppLifecycleState.detached);

    expect(log, ['inactive', 'hide', 'pause', 'detach']);
  });

  testWidgets('engine started in the background from detached', (tester) async {
    // Android can start the engine with no visible activity, for example for
    // a push message. Flutter reports this by walking up from detached, so
    // listeners see the same steps an AppLifecycleListener would.
    start(tester, AppLifecycleState.detached);

    await sendPlatformState(tester, AppLifecycleState.paused);

    expect(log, ['resume', 'inactive', 'hide', 'pause']);
    expect(scope.state.value, AppLifecycleState.paused);
  });

  testWidgets('the first state on a cold start only fires its own callback',
      (tester) async {
    start(tester, null);
    expect(scope.state.value, isNull);

    await sendPlatformState(tester, AppLifecycleState.inactive);
    await sendPlatformState(tester, AppLifecycleState.resumed);

    expect(log, ['inactive', 'resume']);
  });
}
