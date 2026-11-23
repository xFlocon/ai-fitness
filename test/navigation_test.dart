import 'package:ai_fitness/app/app.dart';
import 'package:ai_fitness/core/store.dart';
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'core_test.dart' show profile;

void main() {
  testWidgets('primeira execução abre onboarding; campos validam', (
    tester,
  ) async {
    final store = LocalStore(NativeDatabase.memory());
    addTearDown(store.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: const FitnessApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Seu ponto de partida'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Continuar'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Texto ausente'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('cinco abas navegam sem dados de demonstração', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = LocalStore(NativeDatabase.memory());
    addTearDown(store.close);
    await store.put('profile', {
      ...profile,
      'days': 3,
      'minutes': 30,
      'experience': 'Iniciante',
    }, id: 'profile');
    await store.put('settings', {'reduceMotion': true}, id: 'appearance');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: const FitnessApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ENERGIA DO DIA'), findsOneWidget);
    for (final pair in [
      ('Alimentação', 'Nutrir é cuidar.'),
      ('Treinos', 'Seu corpo em movimento.'),
      ('Assistente', 'Vamos conversar.'),
      ('Perfil', 'Teste'),
    ]) {
      await tester.tap(find.text(pair.$1).last);
      await tester.pumpAndSettle();
      expect(find.text(pair.$2), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
