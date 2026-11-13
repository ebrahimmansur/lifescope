import 'package:flutter/widgets.dart';

/// The states between [AppLifecycleState.resumed] and
/// [AppLifecycleState.paused], in order.
const List<AppLifecycleState> _ladder = [
  AppLifecycleState.resumed,
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

/// Returns every state the app passes through to get from [from] to [to].
///
/// The platform may jump straight from one state to another (for example
/// `resumed` to `paused`). Listeners still expect the states in between, so
/// they are filled in here. The result never contains [from] and always ends
/// with [to], unless the two are equal, in which case it is empty.
///
/// A `null` [from] means the state was unknown, and only [to] is returned.
List<AppLifecycleState> expandTransition(
  AppLifecycleState? from,
  AppLifecycleState to,
) {
  if (from == to) return const [];
  if (from == null) return [to];

  if (to == AppLifecycleState.detached) {
    return [..._walk(from, AppLifecycleState.paused), to];
  }
  if (from == AppLifecycleState.detached) {
    return [
      AppLifecycleState.resumed,
      ..._walk(AppLifecycleState.resumed, to),
    ];
  }
  return _walk(from, to);
}

List<AppLifecycleState> _walk(AppLifecycleState from, AppLifecycleState to) {
  final start = _ladder.indexOf(from);
  final end = _ladder.indexOf(to);
  if (start == end) return const [];
  final step = end > start ? 1 : -1;
  return [
    for (var i = start + step; i != end + step; i += step) _ladder[i],
  ];
}
