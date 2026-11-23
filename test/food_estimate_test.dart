import 'dart:convert';

import 'package:ai_fitness/core/models.dart';
import 'package:ai_fitness/core/store.dart';
import 'package:ai_fitness/features/food_analysis/analysis.dart';
import 'package:ai_fitness/features/nutrition/nutrition.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

// Synthetic fixture tests arithmetic and labeling, not nutritional accuracy.
final estimate = <String, dynamic>{
  'name': 'Coxinha média',
  'grams': 100,
  'per100': {'kcal': 280, 'protein': 10, 'carbs': 35, 'fat': 11, 'fiber': 2},
  'uncertainty': 'Assumida uma unidade de 100 g, frita, com frango. Peso, recheio e óleo variam.',
};
List<Json> validate(Json food) => validateFoodAnalysis(
  jsonEncode({
    'foods': [food],
  }),
);

void main() {
  test('IA preenche porção e nutrientes sem alegar fonte verificada', () {
    final result = validate({
      ...estimate,
      'source': 'TBCA consultada',
      'estimated': false,
    }).single;
    final food = Ingredient.fromJson(result);
    expect(food.estimated, true);
    expect(food.source, contains('não verificada'));
    expect(food.source, isNot(contains('TBCA')));
    expect(food.uncertainty, contains('óleo'));
    expect(food.total.kcal, 280);
    final changed = Ingredient.fromJson({...food.toJson(), 'grams': 150});
    expect(changed.total.kcal, 420);
    expect(changed.total.protein, 15);
    expect(changed.total.carbs, 52.5);
    expect(changed.total.fat, 16.5);
    expect(changed.total.fiber, 3);
  });
  test(
    'valores nutricionais inválidos nunca entram como zeros silenciosos',
    () {
      for (final values in [
        null,
        {'kcal': 280},
        {...estimate['per100'] as Json, 'kcal': -1},
        {...estimate['per100'] as Json, 'kcal': 'NaN'},
        {...estimate['per100'] as Json, 'kcal': 951},
        {...estimate['per100'] as Json, 'kcal': 0},
        {...estimate['per100'] as Json, 'protein': 90},
        {...estimate['per100'] as Json, 'fiber': 90},
      ]) {
        expect(
          () => validate({...estimate, 'per100': values}),
          throwsFormatException,
        );
      }
      for (final grams in [0, -1, 5001, 'Infinity']) {
        expect(
          () => validate({...estimate, 'grams': grams}),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'registros antigos e refeições novas preservam origem sem migração',
    () async {
      final old = {...estimate, 'source': 'Rótulo'}..remove('uncertainty');
      expect(Ingredient.fromJson(old).estimated, false);
      final store = LocalStore(NativeDatabase.memory());
      addTearDown(store.close);
      final food = Ingredient.fromJson(validate(estimate).single);
      final meal = Meal(
        name: 'Lanche',
        category: 'Lanche',
        date: DateTime(2026, 11, 23),
        ingredients: [food],
      );
      await store.put('meal', meal.toJson(), id: 'test-meal');
      final restored = Meal.fromJson((await store.get('test-meal'))!);
      expect(restored.ingredients.single.estimated, true);
      expect(restored.ingredients.single.uncertainty, food.uncertainty);
      expect(restored.total.kcal, 280);
      expect(jsonEncode(await store.export()), contains('Estimativa da IA'));
    },
  );
  testWidgets(
    'estimativa adiciona ingredientes para revisão, sem gravar diário',
    (tester) async {
      final store = LocalStore(NativeDatabase.memory());
      addTearDown(store.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storeProvider.overrideWithValue(store)],
          child: const MaterialApp(home: MealEditor()),
        ),
      );
      await tester.pumpAndSettle();
      await tester
          .widget<FoodAnalysis>(find.byType(FoodAnalysis))
          .onFoods(validate(estimate));
      await tester.pumpAndSettle();
      expect(find.byType(IngredientDialog), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Coxinha média'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Estimativa da IA • peso e nutrientes aproximados'),
        findsOneWidget,
      );
      expect(await store.list('meal'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('editor mantém valores estimados e recalcula porção', (
    tester,
  ) async {
    final food = Ingredient.fromJson(validate(estimate).single);
    Ingredient? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<Ingredient>(
                  context: context,
                  builder: (_) => IngredientDialog(initial: food),
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Mantém valores estimados pela IA'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), '150');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(result!.estimated, true);
    expect(result!.total.kcal, 420);
    expect(result!.uncertainty, food.uncertainty);
  });
  for (final favorite in [false, true]) {
    for (final title in ['   ', 'Meu lanche']) {
      testWidgets('salvar refeição favorite=$favorite nome="$title"', (
        tester,
      ) async {
        final store = LocalStore(NativeDatabase.memory());
        addTearDown(store.close);
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('Diário')),
            ),
            GoRoute(path: '/meal', builder: (_, _) => const MealEditor()),
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
        router.push('/meal');
        await tester.pumpAndSettle();
        await tester
            .widget<FoodAnalysis>(find.byType(FoodAnalysis))
            .onFoods(validate(estimate));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Nome da refeição (opcional)'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.labelText == 'Nome da refeição (opcional)',
          ),
          title,
        );
        tester.testTextInput.hide();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        final button = find.text(
          favorite ? 'Salvar refeição favorita' : 'Já comi • registrar',
        );
        await tester.scrollUntilVisible(
          button,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        final records = await store.list(favorite ? 'favorite' : 'meal');
        expect(records, hasLength(1));
        final meal = Meal.fromJson(records.single.data);
        expect(meal.name, title.trim().isEmpty ? 'Almoço' : title);
        expect(meal.ingredients.single.estimated, true);
        expect(meal.total.kcal, 280);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
