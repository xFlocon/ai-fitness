import 'package:ai_fitness/app/app.dart';
import 'package:ai_fitness/core/store.dart';
import 'package:fl_chart/fl_chart.dart';
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
  testWidgets('seis abas navegam sem dados de demonstração', (tester) async {
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
    final now = DateTime.now();
    for (final (daysAgo, load) in [(2, 20), (1, 35)]) {
      await store.put('session', {
        'date': now.subtract(Duration(days: daysAgo)).toIso8601String(),
        'finished': true,
        'sets': [
          {'load': load, 'index': 0, 'exercise': 'Exercício teste'},
        ],
      });
    }
    for (final (daysAgo, weight) in [(2, 85), (1, 83)]) {
      await store.put('weight', {
        'date': now.subtract(Duration(days: daysAgo)).toIso8601String(),
        'weight': weight,
      });
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: const FitnessApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ENERGIA DO DIA'), findsOneWidget);
    expect(find.text('Fibras'), findsOneWidget);
    expect(find.text('0 / 26 g'), findsOneWidget);
    for (final pair in [
      ('Alimentação', 'Nutrir é cuidar.'),
      ('Treinos', 'Seu corpo em movimento.'),
      ('Cardio', 'Caminhada e pedalada'),
      ('Assistente', 'Vamos conversar.'),
      ('Perfil', 'Teste'),
    ]) {
      await tester.tap(find.text(pair.$1).last);
      await tester.pumpAndSettle();
      expect(find.text(pair.$2), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    final statistics = find.text('Estatísticas');
    await tester.scrollUntilVisible(
      statistics,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(statistics);
    await tester.pumpAndSettle();
    await tester.tap(statistics);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Ainda sem registros neste período'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carga máxima').last);
    await tester.pumpAndSettle();
    expect(find.text('35,0 kg'), findsOneWidget);
    expect(
      tester.widget<BarChart>(find.byType(BarChart)).data.barGroups,
      hasLength(7),
    );
    await tester.tap(find.text('1 ano'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BarChart>(find.byType(BarChart)).data.barGroups,
      hasLength(13),
    );
    expect(find.text('35,0 kg'), findsOneWidget);
    Navigator.of(tester.element(find.text('Estatísticas'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Início').last);
    await tester.pumpAndSettle();
    final cardTitle = find.text('Sua evolução');
    await tester.scrollUntilVisible(
      cardTitle,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(cardTitle);
    await tester.pumpAndSettle();
    expect(find.text('Evolução corporal'), findsOneWidget);
    Navigator.of(tester.element(find.text('Evolução corporal'))).pop();
    await tester.pumpAndSettle();
    final chart = find.byType(LineChart);
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();
    final area = tester.getRect(chart);
    await tester.tapAt(
      area.topLeft + Offset(area.width * .30, area.height * .15),
    );
    await tester.pumpAndSettle();
    expect(find.text('Evolução corporal'), findsOneWidget);
    expect(find.text('Variação no período: -2,0 kg'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
