import 'package:ai_fitness/core/models.dart';
import 'package:ai_fitness/features/workouts/exercise_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'catálogo offline tem mídias e limita a seleção ao equipamento e foco',
    () async {
      final catalog = await loadExerciseCatalog();
      expect(catalog.length, 1388);
      final online = catalog.values.where((e) => e['kind'] == 'online-gif');
      expect(online, hasLength(1255));
      expect(catalog.values.where((e) => e['sha256'] != null), hasLength(1260));
      expect(online.where(verifiedMedia), hasLength(29));
      for (final id in ['flow-0002', 'flow-0006']) {
        expect(catalog[id]?['kind'], 'online-gif');
        expect(hasDemonstration({'catalogId': id}, catalog), isTrue);
      }
      expect(verifiedMedia(catalog['flow-0001']), isFalse);
      expect(hasDemonstration({'catalogId': 'flow-0001'}, catalog), isTrue);
      expect(hasDemonstration({'catalogId': 'inexistente'}, catalog), isFalse);
      final flat = searchExerciseCatalog(
        catalog.values,
        'supino reto com halteres',
      );
      expect(flat.map((e) => e['id']), contains('clip-c01'));
      expect(flat.map((e) => e['id']), isNot(contains('clip-c02')));
      expect(
        searchExerciseCatalog(
          catalog.values,
          'flexão na parede',
        ).map((e) => e['id']),
        contains('flow-0659'),
      );
      expect(
        searchExerciseCatalog(
          catalog.values,
          'skier jacks',
          mediaOnly: true,
        ).map((e) => e['id']),
        contains('commons-06'),
      );
      expect(
        searchExerciseCatalog(
          catalog.values,
          'leg raises deitada',
        ).map((e) => e['id']),
        contains('commons-05'),
      );
      expect(
        online.every(
          (e) =>
              e['still'] == null &&
              hasDemonstration({'catalogId': e['id']}, catalog),
        ),
        isTrue,
      );
      final files = (await AssetManifest.loadFromAssetBundle(rootBundle))
          .listAssets()
          .toSet();
      for (final e in catalog.values) {
        final id = e['id'];
        expect(exerciseCatalogId(id), id);
        final kind = e['kind'];
        if (kind == null || kind == 'online-gif') continue;
        expect(files, contains('assets/exercises/media/$id.${e['still']}'));
        if (kind != 'image') {
          expect(files, contains('assets/exercises/media/$id.$kind'));
        }
        if (e['second'] != null) {
          expect(files, contains('assets/exercises/media/${e['second']}'));
        }
      }
      final home = workoutCandidates(
        catalog.values,
        {'Abdômen'},
        {'body weight'},
        'dead bug',
      );
      expect(home.length, lessThanOrEqualTo(24));
      expect(home.first['id'], 'flow-0276');
      expect(
        home.every((e) => (e['gear'] as List).every((g) => g == 'body weight')),
        isTrue,
      );
      final weights = workoutCandidates(
        catalog.values,
        {'Peito'},
        {'body weight', 'bench', 'dumbbell'},
        'supino reto com halteres',
      );
      expect(weights.first['id'], 'clip-c01');
      expect(weights.any((e) => e['id'] == 'clip-c02'), isFalse);
      final allowed = {'flow-0276': catalog['flow-0276']!};
      expect(
        () => selectedCatalogExercise({'catalogId': 'clip-c01'}, allowed),
        throwsFormatException,
      );
      final selected = selectedCatalogExercise({
        'catalogId': 'flow-0276',
        'name': 'Outro exercício',
      }, allowed);
      expect(selected['name'], 'Dead bug');
      expect(hasDemonstration(selected, catalog), isTrue);
      expect(hasDemonstration({'videoId': 'dQw4w9WgXcQ'}, catalog), isTrue);
      final record = {
        ...selected,
        'muscle': 'Abdômen',
        'sets': 2,
        'reps': 8,
        'rest': 60,
        'instructions': 'Execução.',
        'safety': 'Cuidados.',
        'alternatives': 'Alternativas.',
      };
      final saved = validateWorkout({
        'name': 'Casa',
        'exercises': [
          {...record, 'name': 'Abdominal curto', 'catalogId': 'flow-0001'},
          record,
          {...record, 'name': 'Sem mídia', 'catalogId': null},
        ],
      });
      expect((saved['exercises'] as List).map((e) => e['catalogId']), [
        'flow-0001',
        'flow-0276',
        null,
      ]);
    },
  );

  testWidgets('demonstração do catálogo troca miniatura por GIF sem rede', (
    tester,
  ) async {
    await tester.runAsync(loadExerciseCatalog);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ExerciseDemonstration({'catalogId': 'flow-0276'})),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      const AssetImage('assets/exercises/media/flow-0276.png'),
    );
    await tester.tap(find.text('Reproduzir GIF offline'));
    await tester.pump();
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      const AssetImage('assets/exercises/media/flow-0276.gif'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
