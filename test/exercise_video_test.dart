import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_fitness/core/models.dart';
import 'package:ai_fitness/features/workouts/exercise_video.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'core_test.dart' show workout;

void main() {
  const id = 'abcdefghijk';
  test(
    'dead bug usa nome comum na segunda busca sem aceitar vídeo rejeitado',
    () async {
      final youtube = _YouTube(semantic: true);
      final dio = Dio()..httpClientAdapter = youtube;
      addTearDown(dio.close);
      expect(
        await findExerciseVideos(
          ['dead bug with arm movement'],
          'test-key',
          names: ['Dead bug com movimento dos braços'],
          portugueseQueries: ['dead bug com movimento dos braços'],
          client: dio,
          choose: (_) async => [null],
        ),
        [null],
      );
      expect(youtube.queries, [
        'dead bug with arm movement|dead bug com movimento dos braços',
        'dead bug exercise',
      ]);
    },
  );
  test(
    'repete só a busca de marcha no lugar e preserva a seleção anterior',
    () async {
      final youtube = _YouTube(semantic: true);
      final dio = Dio()..httpClientAdapter = youtube;
      addTearDown(dio.close);
      expect(
        await findExerciseVideos(
          ['dumbbell hammer curl', 'march in place'],
          'test-key',
          names: ['Rosca martelo com halteres', 'Marcha no lugar'],
          portugueseQueries: ['rosca martelo com halteres', 'marcha no lugar'],
          client: dio,
          choose: (rows) async {
            if (rows.first.isNotEmpty) return [id, null];
            expect(rows[1].single['title'], 'How to March in Place');
            return [null, 'march123456'];
          },
        ),
        [id, 'march123456'],
      );
      expect(youtube.queries, [
        'dumbbell hammer curl|rosca martelo com halteres',
        'march in place|marcha no lugar',
        'marching in place exercise',
      ]);
    },
  );
  test('português e inglês dividem uma busca por par de termos', () async {
    final youtube = _YouTube();
    final dio = Dio()..httpClientAdapter = youtube;
    addTearDown(dio.close);
    expect(
      await findExerciseVideos(
        ['dumbbell hammer curl', 'dumbbell hammer curl'],
        'test-key',
        portugueseQueries: [
          'rosca martelo com halteres',
          'rosca martelo com halteres',
        ],
        client: dio,
      ),
      [id, id],
    );
    expect(youtube.queries, [
      'dumbbell hammer curl|rosca martelo com halteres',
    ]);
    expect(youtube.calls, 2); // Uma busca e um lote de detalhes.
  });
  test(
    'IA recebe candidatos curtos e não pode escolher ID de outro exercício',
    () async {
      final dio = Dio()..httpClientAdapter = _YouTube(semantic: true);
      addTearDown(dio.close);
      final results = await findExerciseVideos(
        ['dumbbell hammer curl', 'incline bench press'],
        'test-key',
        client: dio,
        choose: (rows) async {
          expect(
            rows.first.map((v) => v['id']),
            containsAll([id, 'wrong123456']),
          );
          expect(
            rows.first.map((v) => v['id']),
            isNot(contains('long1234567')),
          );
          expect(rows.first.first['description'], 'Demonstração');
          return [id, id];
        },
      );
      expect(results, [id, null]);
    },
  );
  test('aceita apenas IDs do YouTube e ignora links inventados pela IA', () {
    final link = 'https://www.youtube.com/shorts/$id';
    expect(youtubeVideoId(link), id);
    expect(youtubeVideoId('https://youtu.be/$id?t=3'), id);
    expect(
      youtubeVideoId('https://www.youtube.com.fake.test/watch?v=$id'),
      isNull,
    );
    expect(youtubeVideoId('javascript:$id'), isNull);
    final routine = {
      ...workout,
      'exercises': [
        {...(workout['exercises'] as List).single as Json, 'videoId': link},
      ],
    };
    expect(
      (validateWorkout(routine)['exercises'] as List).single['videoId'],
      id,
    );
    expect(
      (validateWorkout(routine, generated: true)['exercises'] as List)
          .single['videoId'],
      isNull,
    );
  });

  test('busca deduplica termos e aceita apenas vídeos públicos curtos incorporáveis', () async {
    final dio = Dio()..httpClientAdapter = _YouTube();
    addTearDown(dio.close);
    final results = await findExerciseVideos(
      ['dumbbell hammer curl', 'dumbbell hammer curl', 'incline bench press'],
      'test-key',
      names: [
        'Rosca martelo com halteres',
        'Rosca martelo com halteres',
        'Supino inclinado',
      ],
      client: dio,
    );
    expect(results, [id, id, null]);
    expect((dio.httpClientAdapter as _YouTube).calls, 3);
  });
}

class _YouTube implements HttpClientAdapter {
  final bool semantic;
  _YouTube({this.semantic = false});
  int calls = 0;
  final queries = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    expect(options.uri.host, 'www.googleapis.com');
    expect(options.headers['X-Goog-Api-Key'], 'test-key');
    expect(options.uri.toString(), isNot(contains('test-key')));
    const valid = 'abcdefghijk';
    const long = 'long1234567';
    const wrong = 'wrong123456';
    const compilation = 'top12345678';
    const march = 'march123456';
    final search = options.uri.path.endsWith('/search');
    if (search) {
      expect(options.queryParameters['videoEmbeddable'], 'true');
      queries.add(options.queryParameters['q'] as String);
    }
    final items = search
        ? [
            for (final entry
                in ((options.queryParameters['q'] as String).startsWith(
                          'dumbbell',
                        )
                        ? {
                            wrong: 'Barbell Hammer Curl Tutorial',
                            compilation:
                                'Top 5 Dumbbell Hammer Curl Variations',
                            long: 'How to Dumbbell Hammer Curl',
                            valid: 'Como fazer rosca martelo com halteres',
                          }
                        : options.queryParameters['q'] ==
                              'marching in place exercise'
                        ? {march: 'How to March in Place'}
                        : {wrong: 'Decline Bench Press Tutorial'})
                    .entries)
              {
                'id': {'videoId': entry.key},
                'snippet': {
                  'title': entry.value,
                  'description': 'Demonstração',
                },
              },
          ]
        : [
            for (final id in [
              long,
              valid,
              if (semantic) ...[wrong, march],
            ])
              {
                'id': id,
                'status': {'embeddable': true, 'privacyStatus': 'public'},
                'contentDetails': {'duration': id == long ? 'PT4M' : 'PT35S'},
              },
          ];
    if (!search && !semantic) {
      expect(
        (options.queryParameters['id'] as String).split(','),
        unorderedEquals([long, valid]),
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'items': items}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
