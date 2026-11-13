import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifescope/src/transitions.dart';

void main() {
  const resumed = AppLifecycleState.resumed;
  const inactive = AppLifecycleState.inactive;
  const hidden = AppLifecycleState.hidden;
  const paused = AppLifecycleState.paused;
  const detached = AppLifecycleState.detached;

  test('same state produces nothing', () {
    expect(expandTransition(paused, paused), isEmpty);
  });

  test('unknown previous state jumps straight to the target', () {
    expect(expandTransition(null, hidden), [hidden]);
  });

  test('adjacent states produce a single step', () {
    expect(expandTransition(resumed, inactive), [inactive]);
    expect(expandTransition(hidden, inactive), [inactive]);
  });

  test('going to background fills in the skipped states', () {
    expect(expandTransition(resumed, paused), [inactive, hidden, paused]);
  });

  test('coming back to foreground fills in the skipped states', () {
    expect(expandTransition(paused, resumed), [hidden, inactive, resumed]);
  });

  test('detaching walks down to paused first', () {
    expect(
      expandTransition(inactive, detached),
      [hidden, paused, detached],
    );
    expect(expandTransition(paused, detached), [detached]);
  });

  test('leaving detached starts from resumed', () {
    expect(expandTransition(detached, resumed), [resumed]);
    expect(expandTransition(detached, hidden), [resumed, inactive, hidden]);
  });
}
