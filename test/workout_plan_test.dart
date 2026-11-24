import 'package:ai_fitness/core/models.dart';
import 'package:ai_fitness/core/store.dart';
import 'package:ai_fitness/features/workouts/workouts.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core_test.dart' show workout, profile;

void main() {
  testWidgets('quadradinho registra e desmarca; lápis edita apenas a série', (
    tester,
  ) async {
    final store = LocalStore(NativeDatabase.memory());
    addTearDown(store.close);
    await store.put('workout', validateWorkout(workout), id: 'test');
    const app = MaterialApp(home: WorkoutSession(id: 'test'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: app,
      ),
    );
    await tester.pumpAndSettle();
    final checkbox = find.byType(Checkbox).first;
    await tester.scrollUntilVisible(checkbox, 200);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.widget<Checkbox>(checkbox).value, true);
    expect((await store.list('session')).single.data['sets'], [
      {'exercise': 'Exercício teste', 'index': 0, 'reps': 10, 'load': 0},
    ]);
    await tester.tap(find.byTooltip('Editar série 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '8');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Série 1 • 8 repetições'), findsOneWidget);
    expect(
      ((await store.list('session')).single.data['sets'] as List)
          .single['load'],
      2,
    );
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox).value, false);
    expect((await store.list('session')).single.data['sets'], isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  });

  Json withRest(Object? rest) => {
    ...workout,
    'exercises': [
      {...(workout['exercises'] as List).single as Json, 'rest': rest},
    ],
  };
  test('IA usa 60 segundos somente para descanso zero ou ausente, carga sempre zero', () {
    for (final rest in [null, 0, '0']) {
      final result = validateWorkout(withRest(rest), generated: true);
      expect((result['exercises'] as List).single['rest'], 60);
    }
    final result = validateWorkout({
      ...workout,
      'exercises': [
        {...(workout['exercises'] as List).single as Json, 'load': 50},
      ],
    }, generated: true);
    expect((result['exercises'] as List).single['load'], 0);
  });
  test(
    'descanso inválido identifica exercício e unidade sem adivinhar minutos',
    () {
      for (final rest in [-1, 1, 601, '1 minuto', '60s', 'NaN', 60.5]) {
        expect(
          () => validateWorkout(withRest(rest), generated: true),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'campo',
              contains('Exercício teste: descanso em segundos'),
            ),
          ),
        );
      }
      expect(() => validateWorkout(withRest(0)), throwsFormatException);
      for (final rest in [10, 60, 600]) {
        expect(
          (validateWorkout(withRest(rest))['exercises'] as List).single['rest'],
          rest,
        );
      }
    },
  );
  test(
    'agenda aceita dias válidos, mantém legado e recusa dados inválidos',
    () {
      expect(validateWorkout(workout)['days'], isEmpty);
      expect(
        validateWorkout({
          ...workout,
          'days': [5, 1],
          'focus': ['Braços'],
          'preferences': 'Halteres',
        })['days'],
        [1, 5],
      );
      for (final days in [
        [0],
        [8],
        [1, 1],
        ['Segunda'],
        'Segunda',
      ]) {
        expect(
          () => validateWorkout({...workout, 'days': days}),
          throwsFormatException,
        );
      }
      expect(
        () => validateWorkout({
          ...workout,
          'focus': ['Inválido'],
        }),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'editor salva dias e foco, reabre e permite rotina diferente em outro dia',
    (tester) async {
      final store = LocalStore(NativeDatabase.memory());
      addTearDown(store.close);
      await store.put('workout', workout, id: 'arms');
      await store.put('workout', {
        ...workout,
        'name': 'Terça abdômen',
        'days': [2],
        'focus': ['Abdômen'],
      }, id: 'core');
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: WorkoutsPage()),
          ),
          GoRoute(
            path: '/workout',
            builder: (_, _) => const WorkoutEditor(id: 'arms'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storeProvider.overrideWithValue(store)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      router.push('/workout');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Segunda'));
      await tester.tap(find.widgetWithText(FilterChip, 'Quarta'));
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Braços'));
      await tester.tap(find.widgetWithText(FilterChip, 'Braços'));
      final button = find.text('Confirmar e salvar treino');
      await tester.scrollUntilVisible(
        button,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final saved = (await store.get('arms'))!;
      expect(saved['days'], [1, 3]);
      expect(saved['focus'], ['Braços']);
      expect((await store.get('core'))!['days'], [2]);
      expect(find.text('Sua semana'), findsOneWidget);
      router.push('/workout');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Segunda'))
            .selected,
        true,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Terça'))
            .selected,
        false,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Braços'))
            .selected,
        true,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('geração mantém bloqueio clínico antes de qualquer envio', (
    tester,
  ) async {
    final store = LocalStore(NativeDatabase.memory());
    addTearDown(store.close);
    await store.put('profile', {...profile, 'clinical': true}, id: 'profile');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: const MaterialApp(home: WorkoutEditor()),
      ),
    );
    await tester.pumpAndSettle();
    final generate = find.text('Gerar sugestão com IA');
    await tester.scrollUntilVisible(
      generate,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(generate);
    await tester.pumpAndSettle();
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.textContaining('Geração automática bloqueada'), findsOneWidget);
    expect(await store.list('workout'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
