import 'dart:convert';
import 'dart:io';

import 'package:ai_fitness/core/ai.dart';
import 'package:ai_fitness/core/models.dart';
import 'package:ai_fitness/core/store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const profile = <String, dynamic>{
  'name': 'Teste',
  'age': 30,
  'height': 175,
  'weight': 80,
  'activity': 1.2,
  'formulaSex': 'male',
  'goal': 'Emagrecer',
};
const food = Ingredient(
  name: 'Alimento de teste',
  grams: 150,
  per100: Macros(200, 10, 30, 4, 2),
  source: 'Fixture de teste; não é dado alimentar real',
);
final workout = <String, dynamic>{
  'name': 'Treino de teste',
  'exercises': [
    <String, dynamic>{
      'name': 'Exercício teste',
      'muscle': 'Pernas',
      'sets': 3,
      'reps': 10,
      'rest': 60,
      'load': 0,
      'instructions': 'Instrução teste',
      'safety': 'Parar em caso de dor',
      'alternatives': 'Consultar profissional',
    },
  ],
};

void main() {
  late LocalStore store;
  bool closed = false;
  setUp(() {
    store = LocalStore(NativeDatabase.memory());
    closed = false;
  });
  tearDown(() async {
    if (!closed) await store.close();
  });
  test('Mifflin-St Jeor com déficit conservador e macros consistentes', () {
    final target = calculateTargets(profile)!;
    expect(target.macros.fiber, 26);
    expect(target.expenditure, closeTo(2098.5, .01));
    expect(target.macros.kcal, closeTo(1888.65, .01));
    expect(
      target.macros.protein * 4 +
          target.macros.carbs * 4 +
          target.macros.fat * 9,
      closeTo(target.macros.kcal, .01),
    );
    expect(
      calculateTargets({...profile, 'goal': 'Ganhar massa muscular'})!
          .macros
          .kcal,
      closeTo(2098.5 * 1.05, .01),
    );
    expect(
      calculateTargets({...profile, 'formulaSex': 'female'})!.expenditure,
      closeTo(1899.3, .01),
    );
  });
  test('meta antiga ganha fibras sem alterar calorias ou macros', () {
    final old = Macros(2030, 119, 236, 68).toJson();
    expect(Macros.fromTargets(old).toJson(), {...old, 'fiber': 28});
    expect(Macros.fromTargets({...old, 'fiber': 32}).fiber, 32);
    expect(Macros.fromJson(old).fiber, 0);
  });
  test('bloqueios clínicos, gestação, menores e ausência de coeficiente', () {
    for (final extra in [
      {'age': 17},
      {'pregnant': true},
      {'clinical': true},
      {'formulaSex': 'none'},
    ]) {
      expect(calculateTargets({...profile, ...extra}), isNull);
    }
    expect(
      () => calculateTargets({...profile, 'weight': -10}),
      throwsFormatException,
    );
    expect(() => number(double.nan), throwsFormatException);
  });
  test(
    'persistência e exclusão de refeições; macro atualiza após edição',
    () async {
      final meal = Meal(
        name: 'Almoço teste',
        category: 'Almoço',
        date: DateTime(2026, 5, 1, 12),
        ingredients: [food],
      );
      final id = await store.put('meal', meal.toJson());
      expect((await store.list('meal')).length, 1);
      expect((await store.daily(meal.date)).kcal, 300);
      expect((await store.daily(meal.date)).protein, 15);
      expect(
        (await store.daily(meal.date.add(const Duration(days: 1)))).kcal,
        0,
      );
      final edited = Meal(
        name: meal.name,
        category: meal.category,
        date: meal.date,
        ingredients: [food, food],
      );
      await store.put('meal', edited.toJson(), id: id);
      expect((await store.daily(meal.date)).carbs, 90);
      await store.remove(id);
      expect((await store.daily(meal.date)).kcal, 0);
    },
  );
  test('peso, criação e edição de treinos persistem', () async {
    final id = await store.put('weight', {
      'weight': 75.5,
      'date': '2026-05-01T10:00:00',
    });
    expect((await store.get(id))!['weight'], 75.5);
    final training = await store.put('workout', validateWorkout(workout));
    await store.put(
      'workout',
      validateWorkout({...workout, 'name': 'Editado'}),
      id: training,
    );
    expect((await store.get(training))!['name'], 'Editado');
    expect((await store.list('workout')).length, 1);
    await store.remove(id);
    expect(await store.get(id), isNull);
  });
  test('documentos sobrevivem ao fechamento do SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('aifitness-test-');
    final file = File('${dir.path}/fitness.sqlite');
    await store.close();
    closed = true;
    final db = LocalStore(NativeDatabase(file));
    await db.put('weight', {'weight': 80}, id: 'persistent-weight');
    await db.close();
    final reopened = LocalStore(NativeDatabase(file));
    expect((await reopened.get('persistent-weight'))!['weight'], 80);
    await reopened.close();
    await file.delete();
    await dir.delete();
  });
  test(
    'configuração de provedores, HTTPS, HTTP privado e credenciais',
    () async {
      const cfg = AiConfig(
        id: 'cfg',
        name: 'Teste',
        type: 'Ollama',
        baseUrl: 'http://192.168.1.3:11434/api',
        model: 'local-model',
        localHttp: true,
      );
      expect(cfg.validateUrl().host, '192.168.1.3');
      await store.put('provider', cfg.toJson(), id: cfg.id);
      expect(AiConfig.fromJson((await store.get(cfg.id))!).model, cfg.model);
      for (final url in [
        'http://example.com/v1',
        'http://192.168.1.999/v1',
        'https://key@example.com/v1',
        'file:///tmp/file',
        'https://example.com/v1?key=secret',
      ]) {
        expect(
          () => AiConfig(
            id: '1',
            name: 't',
            type: 'OpenAI',
            baseUrl: url,
            model: 'm',
            localHttp: true,
          ).validateUrl(),
          throwsFormatException,
        );
      }
      expect(
        () => const AiConfig(
          id: '1',
          name: 't',
          type: 'Ollama',
          baseUrl: 'http://127.0.0.1:11434/api',
          model: 'm',
        ).validateUrl(),
        throwsFormatException,
      );
      final exported = jsonEncode(await store.export());
      expect(exported, isNot(contains('local-model')));
    },
  );
  test('JSON inválido, números não finitos e limites são recusados', () {
    expect(
      validateFoodAnalysis(
        '```json\n{"foods":[{"name":"arroz","grams":100,"per100":{"kcal":130,"protein":2.5,"carbs":28,"fat":0.3,"fiber":0.5},"uncertainty":"peso estimado"}]}\n```',
      ).single['grams'],
      100,
    );
    for (final response in [
      '[]',
      '{"foods":[]}',
      '{"foods":[{"name":"x","grams":-1,"uncertainty":"?"}]}',
      'comida',
    ]) {
      expect(() => validateFoodAnalysis(response), throwsFormatException);
    }
    expect(
      () => validateWorkout({...workout, 'exercises': []}),
      throwsFormatException,
    );
    expect(
      () => validateWorkout({
        ...workout,
        'exercises': [
          ...workout['exercises'] as List,
          ...workout['exercises'] as List,
        ],
      }),
      throwsFormatException,
    );
    final exercise = Map<String, dynamic>.from(
      (workout['exercises'] as List).first as Map,
    )..['sets'] = 2.5;
    expect(
      () => validateWorkout({
        ...workout,
        'exercises': [exercise],
      }),
      throwsFormatException,
    );
  });
  test(
    'exportação omite caminhos privados e exclusão remove registros',
    () async {
      await store.put('photo', {
        'photo': '/private/user.jpg',
        'date': '2026-01-01',
      });
      await store.put('chat', {
        'messages': ['sensível'],
      });
      expect(jsonEncode(await store.export()), isNot(contains('/private/')));
      expect(jsonEncode(await store.export()), isNot(contains('sensível')));
      await store.erase();
      expect(await store.list('photo'), isEmpty);
    },
  );
}
