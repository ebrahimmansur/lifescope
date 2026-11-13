import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifescope/lifescope.dart';

void main() {
  late LifeScope scope;

  void moveTo(WidgetTester tester, AppLifecycleState state) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    scope = LifeScope();
  });

  tearDown(() => scope.dispose());

  Widget wrap(Widget child) {
    return LifeScopeProvider.value(scope: scope, child: child);
  }

  testWidgets('calls its callbacks while mounted', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(wrap(LifeScopeListener(
      onHide: () => log.add('hide'),
      onShow: () => log.add('show'),
      child: const SizedBox(),
    )));

    moveTo(tester, AppLifecycleState.hidden);
    moveTo(tester, AppLifecycleState.resumed);

    expect(log, ['hide', 'show']);
  });

  testWidgets('uses the latest callbacks after a rebuild', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(wrap(LifeScopeListener(
      onHide: () => log.add('old'),
      child: const SizedBox(),
    )));
    await tester.pumpWidget(wrap(LifeScopeListener(
      onHide: () => log.add('new'),
      child: const SizedBox(),
    )));

    moveTo(tester, AppLifecycleState.hidden);

    expect(log, ['new']);
  });

  testWidgets('stops listening when removed', (tester) async {
    var calls = 0;
    await tester.pumpWidget(wrap(LifeScopeListener(
      onStateChange: (_) => calls++,
      child: const SizedBox(),
    )));
    await tester.pumpWidget(wrap(const SizedBox()));

    moveTo(tester, AppLifecycleState.hidden);

    expect(calls, 0);
  });

  testWidgets('moves to a new scope when the provider changes', (tester) async {
    final other = LifeScope();
    addTearDown(other.dispose);
    var calls = 0;
    Widget listener() => LifeScopeListener(
          onHide: () => calls++,
          child: const SizedBox(),
        );

    await tester.pumpWidget(wrap(listener()));
    await tester.pumpWidget(
      LifeScopeProvider.value(scope: other, child: listener()),
    );

    // If the listener were still on the old scope it would fire here.
    other.dispose();
    moveTo(tester, AppLifecycleState.hidden);

    expect(calls, 0);
  });
}
