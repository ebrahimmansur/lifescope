import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifescope/lifescope.dart';

void main() {
  late LifeScope scope;

  setUp(() => scope = LifeScope());
  tearDown(() => scope.dispose());

  Widget wrap(Widget child) {
    return LifeScopeProvider.value(scope: scope, child: child);
  }

  testWidgets('vetoes exit while mounted', (tester) async {
    await tester.pumpWidget(wrap(LifeScopeExitGuard(
      onExitRequested: () => AppExitResponse.cancel,
      child: const SizedBox(),
    )));

    expect(
      await tester.binding.handleRequestAppExit(),
      AppExitResponse.cancel,
    );
  });

  testWidgets('stops guarding when removed', (tester) async {
    await tester.pumpWidget(wrap(LifeScopeExitGuard(
      onExitRequested: () => AppExitResponse.cancel,
      child: const SizedBox(),
    )));
    await tester.pumpWidget(wrap(const SizedBox()));

    expect(
      await tester.binding.handleRequestAppExit(),
      AppExitResponse.exit,
    );
  });

  testWidgets('uses the latest callback after a rebuild', (tester) async {
    await tester.pumpWidget(wrap(LifeScopeExitGuard(
      onExitRequested: () => AppExitResponse.cancel,
      child: const SizedBox(),
    )));
    await tester.pumpWidget(wrap(LifeScopeExitGuard(
      onExitRequested: () => AppExitResponse.exit,
      child: const SizedBox(),
    )));

    expect(
      await tester.binding.handleRequestAppExit(),
      AppExitResponse.exit,
    );
  });
}
