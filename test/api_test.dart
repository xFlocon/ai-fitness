import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_fitness/core/ai.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handler;
  Adapter(this.handler);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  for (final type in [
    'OpenAI',
    '9Router',
    'OpenRouter',
    'Gemini',
    'Claude',
    'Ollama',
    'LM Studio',
    'Compatível OpenAI',
  ]) {
    test('$type monta protocolo e lê streaming real em blocos UTF-8', () async {
      final dio = Dio();
      dio.httpClientAdapter = Adapter((request) async {
        final body = request.data as Map;
        expect(request.headers.toString(), isNot(contains('null')));
        if (type == 'Gemini') {
          expect(request.path, contains('streamGenerateContent'));
          expect(body['contents'], isList);
          expect(request.headers['x-goog-api-key'], 'test-key');
        } else if (type == 'Claude') {
          expect(request.path, '/messages');
          expect(request.headers['x-api-key'], 'test-key');
        } else {
          expect(
            request.path,
            type == 'Ollama' ? '/chat' : '/chat/completions',
          );
        }
        final event = switch (type) {
          'Gemini' => {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Olá'},
                  ],
                },
              },
            ],
          },
          'Claude' => {
            'type': 'content_block_delta',
            'delta': {'text': 'Olá'},
          },
          'Ollama' => {
            'message': {'content': 'Olá'},
          },
          _ => {
            'choices': [
              {
                'delta': {'content': 'Olá'},
              },
            ],
          },
        };
        final text =
            '${type == 'Ollama' ? '' : 'data: '}${jsonEncode(event)}\n\n';
        final bytes = utf8.encode(text);
        return ResponseBody(
          Stream.fromIterable(bytes.map((b) => Uint8List.fromList([b]))),
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        );
      });
      final provider = HttpAiProvider(
        AiConfig(
          id: 'test',
          name: 'test',
          type: type,
          baseUrl: 'https://example.com/v1',
          model: 'model',
        ),
        'test-key',
        client: dio,
      );
      expect(
        await provider.generate([
          {'role': 'user', 'content': 'teste'},
        ]).join(),
        'Olá',
      );
    });
  }
  test('falha de autenticação traduzida sem expor corpo ou chave', () async {
    final dio = Dio()
      ..httpClientAdapter = Adapter(
        (_) async => ResponseBody.fromString(
          '{"error":"secret-key"}',
          401,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
    final provider = HttpAiProvider(
      const AiConfig(
        id: 't',
        name: 't',
        type: 'OpenAI',
        baseUrl: 'https://example.com/v1',
        model: 'm',
      ),
      'secret-key',
      client: dio,
    );
    try {
      await provider.generate([
        {'role': 'user', 'content': 'teste'},
      ]).join();
      fail('Deveria falhar.');
    } catch (e) {
      expect(apiError(e), contains('Autenticação'));
      expect(apiError(e), isNot(contains('secret-key')));
    }
  });
  test('JSON malformado e visão não suportada falham', () async {
    final dio = Dio()
      ..httpClientAdapter = Adapter(
        (_) async => ResponseBody.fromString('data: INVALID\n\n', 200),
      );
    final provider = HttpAiProvider(
      const AiConfig(
        id: 't',
        name: 't',
        type: 'OpenAI',
        baseUrl: 'https://example.com/v1',
        model: 'm',
      ),
      '',
      client: dio,
    );
    await expectLater(
      provider.generate([
        {'role': 'user', 'content': 't'},
      ]).join(),
      throwsFormatException,
    );
    await expectLater(
      provider.generate([
        {'role': 'user', 'content': 't'},
      ], image: Uint8List(10)).join(),
      throwsA(isA<AiFailure>()),
    );
  });
  for (final streaming in [true, false]) {
    for (final code in [
      'insufficient_quota',
      'rate_limit_exceeded',
      'unknown',
    ]) {
      test(
        'HTTP 429 $code com streaming=$streaming informa causa sem segredos',
        () async {
          final dio = Dio()
            ..httpClientAdapter = Adapter(
              (_) async => ResponseBody.fromString(
                jsonEncode({
                  'error': {
                    'code': code,
                    'type': code,
                    'message': 'secret-key e dados privados',
                  },
                }),
                429,
                headers: {
                  'content-type': ['application/json'],
                  'retry-after': ['12'],
                },
              ),
            );
          final provider = HttpAiProvider(
            AiConfig(
              id: 't',
              name: 't',
              type: 'OpenAI',
              baseUrl: 'https://example.com/v1',
              model: 'm',
              streaming: streaming,
            ),
            'secret-key',
            client: dio,
          );
          try {
            await provider.generate([
              {'role': 'user', 'content': 'teste'},
            ]).join();
            fail('Deveria falhar.');
          } on DioException catch (error) {
            final message = apiError(error);
            expect(message, isNot(contains('secret-key')));
            expect(message, isNot(contains('dados privados')));
            expect(
              message,
              contains(switch (code) {
                'insufficient_quota' => 'cota ou créditos indisponíveis',
                'rate_limit_exceeded' => '12 segundos',
                _ => 'sem indicar a causa reconhecida',
              }),
            );
          }
        },
      );
    }
  }

  test('HTTP 429 com corpo inválido mantém diagnóstico seguro', () async {
    final dio = Dio()
      ..httpClientAdapter = Adapter(
        (_) async => ResponseBody.fromString('secret-key: not JSON', 429),
      );
    final provider = HttpAiProvider(
      const AiConfig(
        id: 't',
        name: 't',
        type: 'OpenAI',
        baseUrl: 'https://example.com/v1',
        model: 'm',
      ),
      'secret-key',
      client: dio,
    );
    try {
      await provider.generate([
        {'role': 'user', 'content': 'teste'},
      ]).join();
      fail('Deveria falhar.');
    } on DioException catch (error) {
      expect(apiError(error), contains('sem indicar a causa reconhecida'));
      expect(apiError(error), isNot(contains('secret-key')));
    }
  });

  test('descoberta e resposta sem streaming', () async {
    final dio = Dio()
      ..httpClientAdapter = Adapter(
        (request) async => ResponseBody.fromString(
          jsonEncode(
            request.method == 'GET'
                ? {
                    'data': [
                      {'id': 'model'},
                    ],
                  }
                : {
                    'choices': [
                      {
                        'message': {'content': 'OK'},
                      },
                    ],
                  },
          ),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
    final provider = HttpAiProvider(
      const AiConfig(
        id: 't',
        name: 't',
        type: 'OpenAI',
        baseUrl: 'https://example.com/v1',
        model: 'model',
        streaming: false,
      ),
      '',
      client: dio,
    );
    expect(await provider.models(), ['model']);
    expect(
      await provider.generate([
        {'role': 'user', 'content': 't'},
      ]).join(),
      'OK',
    );
  });
}
