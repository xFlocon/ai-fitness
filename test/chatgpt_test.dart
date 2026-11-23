import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_fitness/core/ai.dart';
import 'package:ai_fitness/core/chatgpt.dart';
import 'package:ai_fitness/core/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';

import 'api_test.dart' show Adapter;

class RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = JsonWebKey.generate('RS256');
  final jwks = <String, dynamic>{
    'keys': [
      JsonWebKey.fromCryptoKeys(publicKey: key.cryptoKeyPair.publicKey)
          .toJson(),
    ],
  };
  String sign(Json overrides) {
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = {
        'iss': 'https://auth.openai.com',
        'sub': 'user-test',
        'aud': 'oaiapp_test',
        'exp':
            DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'nonce': 'test-nonce',
        'email': 'test@example.invalid',
        ...overrides,
      }
      ..addRecipient(key, algorithm: 'RS256');
    return builder.build().toCompactSerialization();
  }

  Json saved({bool expired = false}) => {
    'subject': 'user-test',
    'client_id': 'oaiapp_test',
    'email': 'test@example.invalid',
    'access_token': 'access-secret',
    'refresh_token': 'refresh-secret',
    'id_token': 'id-secret',
    'scopes': ['chatgpt.tokens.use.direct'],
    'expires_at': DateTime.now()
        .add(Duration(hours: expired ? -1 : 1))
        .toIso8601String(),
  };
  const cfg = AiConfig(
    id: 'cfg',
    name: 'ChatGPT teste',
    type: chatGptType,
    baseUrl: 'https://api.openai.com/v1',
    model: 'test-model',
    authId: 'oaiapp_test',
    images: true,
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  Future<void> seed({bool expired = false}) =>
      const FlutterSecureStorage().write(
        key: 'chatgpt.accounts',
        value: jsonEncode({'oaiapp_test': saved(expired: expired)}),
      );

  test('PKCE S256 conforme vetor RFC 7636', () {
    expect(
      pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
    expect(oauthRandom(), hasLength(43));
    expect(oauthRandom(), isNot(oauthRandom()));
  });
  test('callback rejeita state, duplicação, troca de client e erro OAuth', () {
    expect(
      validateOAuthCallback(
        Uri.parse(
          'http://127.0.0.1/auth/callback?state=s&code=c&client_id=oaiapp_test',
        ),
        's',
        null,
      ),
      'oaiapp_test',
    );
    for (final query in [
      'state=wrong&code=c&client_id=oaiapp_test',
      'state=s&state=s&code=c&client_id=oaiapp_test',
      'state=s&error=access_denied',
      'state=s&code=c&client_id=dynamic_agent_client',
      'state=s&code=c&client_id=other',
    ]) {
      expect(
        () => validateOAuthCallback(
          Uri.parse('http://127.0.0.1/auth/callback?$query'),
          's',
          'oaiapp_test',
        ),
        throwsA(isA<AiFailure>()),
      );
    }
  });
  test('ID token exige assinatura, emissor, audience, validade, nonce e identidade', () async {
    expect(
      (await verifyChatGptIdentity(
        sign({}),
        jwks,
        'oaiapp_test',
        nonce: 'test-nonce',
      ))['subject'],
      'user-test',
    );
    for (final overrides in <Json>[
      {'iss': 'https://attacker.invalid'},
      {'aud': 'other'},
      {'nonce': 'wrong'},
      {'exp': 1},
      {'sub': 'other'},
      {
        'aud': ['oaiapp_test', 'other'],
      },
      {'azp': 'other'},
    ]) {
      await expectLater(
        verifyChatGptIdentity(
          sign(overrides),
          jwks,
          'oaiapp_test',
          nonce: 'test-nonce',
          subject: 'user-test',
        ),
        throwsA(isA<AiFailure>()),
      );
    }
    await expectLater(
      verifyChatGptIdentity(
        sign({}),
        {'keys': []},
        'oaiapp_test',
        nonce: 'test-nonce',
      ),
      throwsA(isA<AiFailure>()),
    );
    final jwt = sign({}).split('.');
    jwt[1] = base64UrlEncode(utf8.encode('{"sub":"attacker"}'))
        .replaceAll('=', '');
    await expectLater(
      verifyChatGptIdentity(jwt.join('.'), jwks, 'oaiapp_test'),
      throwsA(isA<AiFailure>()),
    );
  });

  test('login completo usa callback loopback real, PKCE e valida assinatura antes de salvar', () async {
    String? nonce, verifierHash, redirect;
    final dio = Dio()
      ..httpClientAdapter = Adapter((r) async {
        if (r.uri.path.endsWith('jwks.json')) {
          return ResponseBody.fromString(
            jsonEncode(jwks),
            200,
            headers: {
              'content-type': ['application/json'],
            },
          );
        }
        final form = r.data as Map;
        expect(form['client_id'], 'oaiapp_test');
        expect(form['redirect_uri'], redirect);
        expect(pkceChallenge(form['code_verifier'] as String), verifierHash);
        expect(form.containsKey('client_secret'), false);
        return ResponseBody.fromString(
          jsonEncode({
            'access_token': 'access-secret',
            'refresh_token': 'refresh-secret',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'scope': 'openid chatgpt.tokens.use.direct',
            'id_token': sign({'nonce': nonce}),
          }),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
    final auth = ChatGptAuth(
      client: dio,
      browser: (url) async {
        expect(url.host, 'auth.openai.com');
        expect(url.queryParameters['client_id'], 'dynamic_agent_client');
        nonce = url.queryParameters['nonce'];
        verifierHash = url.queryParameters['code_challenge'];
        redirect = url.queryParameters['redirect_uri'];
        expect(Uri.parse(redirect!).host, '127.0.0.1');
        final client = HttpOverrides.runWithHttpOverrides(
          () => HttpClient(),
          RealHttp(),
        );
        try {
          final callback = Uri.parse(redirect!).replace(
            queryParameters: {
              'code': 'code-secret',
              'state': url.queryParameters['state']!,
              'client_id': 'oaiapp_test',
            },
          );
          final response = await (await client.getUrl(callback)).close();
          expect(response.statusCode, 200);
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
        return true;
      },
    );
    final id = await auth.signIn(cancel: CancelToken());
    expect(id, 'oaiapp_test');
    expect(await auth.accessToken(id), 'access-secret');
    expect((await auth.accounts()).single['email'], 'test@example.invalid');
    expect(jsonEncode(await auth.accounts()), isNot(contains('access-secret')));
  });

  test('cancelamento fecha listener sem salvar sessão', () async {
    final cancel = CancelToken();
    final auth = ChatGptAuth(
      browser: (_) async {
        cancel.cancel();
        return true;
      },
    );
    await expectLater(auth.signIn(cancel: cancel), throwsA(isA<AiFailure>()));
    expect(await auth.accounts(), isEmpty);
  });

  test('refresh serializado grava rotação e mantém client correto', () async {
    await seed(expired: true);
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = Adapter((r) async {
        calls++;
        expect((r.data as Map)['client_id'], 'oaiapp_test');
        expect((r.data as Map)['refresh_token'], 'refresh-secret');
        return ResponseBody.fromString(
          jsonEncode({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'expires_in': 3600,
            'token_type': 'Bearer',
          }),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
    final auth = ChatGptAuth(client: dio);
    expect(
      await Future.wait([
        auth.accessToken('oaiapp_test'),
        auth.accessToken('oaiapp_test'),
      ]),
      ['new-access', 'new-access'],
    );
    expect(calls, 1);
    final saved = await const FlutterSecureStorage().read(
      key: 'chatgpt.accounts',
    );
    expect(saved, contains('new-refresh'));
    expect(saved, isNot(contains('refresh-secret')));
  });

  for (final code in ['invalid_grant', 'temporary']) {
    test('refresh $code limpa somente sessão inutilizável', () async {
      await seed(expired: true);
      final dio = Dio()
        ..httpClientAdapter = Adapter(
          (_) async => ResponseBody.fromString(
            jsonEncode({'error': code}),
            code == 'invalid_grant' ? 400 : 503,
            headers: {
              'content-type': ['application/json'],
            },
          ),
        );
      final auth = ChatGptAuth(client: dio);
      await expectLater(
        auth.accessToken('oaiapp_test'),
        throwsA(isA<AiFailure>()),
      );
      final a = (await auth.accounts()).single;
      expect(a['connected'], code != 'invalid_grant');
      expect(a['id'], 'oaiapp_test');
    });
  }

  test('logout revoga sessão, cancela envios e preserva registro', () async {
    await seed();
    final dio = Dio()
      ..httpClientAdapter = Adapter((r) async {
        if (r.method == 'GET') {
          return ResponseBody.fromString(
            '{"revocation_endpoint":"https://auth.openai.com/api/accounts/oauth/revoke"}',
            200,
            headers: {
              'content-type': ['application/json'],
            },
          );
        }
        expect((r.data as Map)['token'], 'refresh-secret');
        return ResponseBody.fromString('', 200);
      });
    final auth = ChatGptAuth(client: dio);
    final request = auth.startRequest('oaiapp_test', null);
    expect(await auth.signOut('oaiapp_test'), true);
    expect(request.isCancelled, true);
    final a = (await auth.accounts()).single;
    expect(a['connected'], false);
    expect(a['id'], 'oaiapp_test');
    expect(
      await const FlutterSecureStorage().read(key: 'chatgpt.accounts'),
      isNot(contains('secret')),
    );
  });
  test(
    'logout sem rede limpa tokens e informa revogação não confirmada',
    () async {
      await seed();
      final dio = Dio()
        ..httpClientAdapter = Adapter(
          (_) async => ResponseBody.fromString('', 503),
        );
      final auth = ChatGptAuth(client: dio);
      expect(await auth.signOut('oaiapp_test'), false);
      expect((await auth.accounts()).single['connected'], false);
    },
  );

  for (final terminal in [
    'response.completed',
    'response.failed',
    'response.incomplete',
    'interrupted',
  ]) {
    test('Responses $terminal respeita contrato e exige conclusão', () async {
      await seed();
      final dio = Dio()
        ..httpClientAdapter = Adapter((r) async {
          expect(r.uri.toString(), 'https://api.openai.com/v1/responses');
          expect(r.headers['Authorization'], 'Bearer access-secret');
          final body = r.data as Map;
          expect(body.keys.toSet(), {
            'model',
            'input',
            'store',
            'stream',
            'instructions',
          });
          expect(body['store'], false);
          expect(body['stream'], true);
          expect(
            ((body['input'] as List).last['content'] as List).last['type'],
            'input_image',
          );
          final events = [
            {'type': 'response.output_text.delta', 'delta': 'Olá'},
            if (terminal != 'interrupted')
              {
                'type': terminal,
                'response': {
                  'status': terminal == 'response.completed'
                      ? 'completed'
                      : 'failed',
                  'error': {
                    'code': 'subscription_sharing_usage_limit_exceeded',
                    'message': 'do not display secret',
                  },
                },
              },
          ];
          return ResponseBody.fromString(
            events.map((e) => 'data: ${jsonEncode(e)}\n\n').join(),
            200,
          );
        });
      final p = ChatGptProvider(
        cfg,
        authentication: ChatGptAuth(),
        client: dio,
      );
      final future = p
          .generate(
            [
              {'role': 'user', 'content': 'teste'},
            ],
            system: 'instruções',
            image: Uint8List(10),
          )
          .join();
      if (terminal == 'response.completed') {
        expect(await future, 'Olá');
      } else {
        await expectLater(future, throwsA(isA<AiFailure>()));
      }
    });
  }
  test('catálogo respeita visibilidade e slug da conta', () async {
    await seed();
    final dio = Dio()
      ..httpClientAdapter = Adapter(
        (_) async => ResponseBody.fromString(
          '{"models":[{"slug":"visible","visibility":"list"},{"slug":"hidden","visibility":"hide"}]}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
    expect(
      await ChatGptProvider(
        cfg,
        authentication: ChatGptAuth(),
        client: dio,
      ).models(),
      ['visible'],
    );
  });
  for (final code in [
    'subscription_sharing_user_not_eligible',
    'subscription_sharing_usage_limit_exceeded',
    'unrecognized',
  ]) {
    test('erro HTTP estruturado $code nunca exibe corpo ou segredo', () async {
      await seed();
      final dio = Dio()
        ..httpClientAdapter = Adapter(
          (_) async => ResponseBody.fromString(
            jsonEncode({
              'error': {'code': code, 'message': 'access-secret'},
            }),
            403,
            headers: {
              'content-type': ['application/json'],
              'x-request-id': ['req_test123'],
            },
          ),
        );
      final p = ChatGptProvider(
        cfg,
        authentication: ChatGptAuth(),
        client: dio,
      );
      try {
        await p.generate([
          {'role': 'user', 'content': 'teste'},
        ]).join();
        fail('Deveria falhar.');
      } on AiFailure catch (e) {
        expect(e.message, isNot(contains('access-secret')));
        expect(e.message, contains('req_test123'));
        if (code == 'subscription_sharing_user_not_eligible') {
          expect(e.message, contains('não habilitou'));
        }
        if (code == 'subscription_sharing_usage_limit_exceeded') {
          expect(e.message, contains('Limite autorizado'));
        }
      }
    });
  }
  test('token OAuth nunca aceita servidor personalizado', () {
    expect(
      () => ChatGptProvider(
        const AiConfig(
          id: 'x',
          name: 'x',
          type: chatGptType,
          baseUrl: 'https://attacker.invalid/v1',
          model: 'x',
          authId: 'oaiapp_test',
        ),
      ),
      throwsA(isA<AiFailure>()),
    );
  });
  test(
    'sessões de contas distintas não compartilham token ou permissão',
    () async {
      await const FlutterSecureStorage().write(
        key: 'chatgpt.accounts',
        value: jsonEncode({
          'oaiapp_test': saved(),
          'other': {
            ...saved(),
            'client_id': 'other',
            'access_token': 'other-access',
            'scopes': <String>[],
          },
        }),
      );
      final auth = ChatGptAuth();
      expect(await auth.accessToken('oaiapp_test'), 'access-secret');
      await expectLater(auth.accessToken('other'), throwsA(isA<AiFailure>()));
      expect((await auth.accounts()).length, 2);
      expect(
        jsonEncode(await auth.accounts()),
        isNot(contains('other-access')),
      );
      expect(AiConfig.fromJson(cfg.toJson()).authId, 'oaiapp_test');
    },
  );
}
