import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifescope/lifescope.dart';

void main() {
  testWidgets('of finds the scope from the provider', (tester) async {
    final scope = LifeScope();
    addTearDown(scope.dispose);
    LifeScope? found;

    await tester.pumpWidget(
      LifeScopeProvider.value(
        scope: scope,
        child: Builder(builder: (context) {
          found = LifeScope.of(context);
          return const SizedBox();
        }),
      ),
    );

    expect(found, same(scope));
  });

  testWidgets('of throws a helpful error without a provider', (tester) async {
    late Object error;
    await tester.pumpWidget(Builder(builder: (context) {
      try {
        LifeScope.of(context);
      } catch (e) {
        error = e;
      }
      return const SizedBox();
    }));

    expect(error, isA<FlutterError>());
    expect(error.toString(), contains('LifeScopeProvider'));
  });

  testWidgets('maybeOf returns null without a provider', (tester) async {
    var looked = false;
    LifeScope? found;
    await tester.pumpWidget(Builder(builder: (context) {
      found = LifeScope.maybeOf(context);
      looked = true;
      return const SizedBox();
    }));

    expect(looked, isTrue);
    expect(found, isNull);
  });

  testWidgets('the default provider creates and disposes its scope',
      (tester) async {
    late LifeScope scope;
    await tester.pumpWidget(
      LifeScopeProvider(
        child: Builder(builder: (context) {
          scope = LifeScope.of(context);
          return const SizedBox();
        }),
      ),
    );
    final sub = scope.listen(onHide: () {});

    await tester.pumpWidget(const SizedBox());

    expect(sub.isActive, isFalse);
  });

  testWidgets('a provided value is not disposed with the provider',
      (tester) async {
    final scope = LifeScope();
    addTearDown(scope.dispose);
    final sub = scope.listen(onHide: () {});

    await tester.pumpWidget(
      LifeScopeProvider.value(scope: scope, child: const SizedBox()),
    );
    await tester.pumpWidget(const SizedBox());

    expect(sub.isActive, isTrue);
  });
}
