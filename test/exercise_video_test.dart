import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_fitness/core/models.dart';
import 'package:ai_fitness/features/workouts/exercise_video.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'core_test.dart' show workout;

void main() {
  const id = 'abcdefghijk';
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
      ['curl', 'curl', 'press'],
      'test-key',
      client: dio,
    );
    expect(results, [id, id, null]);
    expect((dio.httpClientAdapter as _YouTube).calls, 3);
  });
}

class _YouTube implements HttpClientAdapter {
  int calls = 0;

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
    final search = options.uri.path.endsWith('/search');
    if (search) expect(options.queryParameters['videoEmbeddable'], 'true');
    final items = search
        ? [
            for (final id in [
              long,
              if ((options.queryParameters['q'] as String).startsWith('curl'))
                valid,
            ])
              {
                'id': {'videoId': id},
              },
          ]
        : [
            for (final id in [long, valid])
              {
                'id': id,
                'status': {'embeddable': true, 'privacyStatus': 'public'},
                'contentDetails': {'duration': id == long ? 'PT4M' : 'PT35S'},
              },
          ];
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
