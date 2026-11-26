import 'package:ai_fitness/core/store.dart';
import 'package:ai_fitness/features/cardio/cardio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test(
    'estimativa usa calorias ativas e não inventa resultado sem distância',
    () {
      expect(
        cardioCalories(bike: false, kg: 70, meters: 5000, seconds: 3600),
        closeTo(205.8, .01),
      );
      expect(
        cardioCalories(bike: true, kg: 70, meters: 18000, seconds: 3600),
        closeTo(426.3, .01),
      );
      expect(
        cardioCalories(bike: false, kg: 70, meters: 0, seconds: 3600),
        isNull,
      );
    },
  );

  testWidgets('caminhada mostra métricas e salva resumo sem coordenadas', (
    tester,
  ) async {
    final store = LocalStore(NativeDatabase.memory());
    addTearDown(store.close);
    await store.put('profile', {'weight': 70}, id: 'profile');
    const channel = MethodChannel('ai_fitness/cardio');
    final messenger = tester.binding.defaultBinaryMessenger;
    var active = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'clear') {
        active = false;
        return null;
      }
      if (call.method == 'start') {
        expect(call.arguments, 'walk');
        active = true;
      }
      return !active
          ? null
          : {
              'id': 'test',
              'mode': 'walk',
              'seconds': 3600,
              'meters': 5000.0,
              'steps': 6800,
              'fixed': true,
              'gps': true,
              'speed': 5.1,
              'ended': call.method == 'finish',
            };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: const MaterialApp(home: Scaffold(body: CardioPage())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('GPS, passos e privacidade'), findsOneWidget);
    await tester.tap(find.text('Iniciar caminhada'));
    await tester.pumpAndSettle();
    expect(find.text('01:00:00'), findsOneWidget);
    expect(find.text('5,00 km'), findsOneWidget);
    expect(find.textContaining('5,1 km/h'), findsOneWidget);
    expect(find.textContaining('6800 passos'), findsOneWidget);
    expect(await store.list('cardio'), isEmpty);
    await tester.tap(find.text('Terminar caminhada'));
    await tester.pumpAndSettle();
    expect(find.text('Caminhada concluída'), findsOneWidget);
    expect(find.textContaining('206 kcal'), findsWidgets);
    final data = (await store.list('cardio')).single.data;
    expect(
      data.keys,
      unorderedEquals([
        'mode',
        'date',
        'seconds',
        'meters',
        'fixed',
        'steps',
        'kcal',
      ]),
    );
    expect(data['steps'], 6800);
    await tester.pumpWidget(const SizedBox());
  });
}
