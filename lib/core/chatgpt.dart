import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jose/jose.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ai.dart';
import 'models.dart';

const chatGptType = 'ChatGPT — assinatura';
const _issuer = 'https://auth.openai.com';
const _resource = 'https://api.openai.com/v1';
const _scopes =
    'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';

String oauthRandom() =>
    base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
String pkceChallenge(String verifier) =>
    base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');

// Pure validation shared by loopback callback and regression tests.
String validateOAuthCallback(Uri callback, String state, String? clientId) {
  final q = callback.queryParametersAll;
  if (q.values.any((v) => v.length != 1) || q['state']?.single != state) {
    throw const AiFailure('Retorno de login inválido. Inicie novo login.');
  }
  if (q.containsKey('error')) {
    throw const AiFailure(
      'Login ou autorização recusados. Nenhuma conexão foi alterada.',
    );
  }
  final issued = q['client_id']?.single ?? clientId;
  if (issued == null ||
      issued.isEmpty ||
      issued.length > 300 ||
      issued == 'dynamic_agent_client' ||
      (clientId != null && issued != clientId) ||
      (q['code']?.single.isEmpty ?? true)) {
    throw const AiFailure(
      'Registro incompleto ou conta diferente. Inicie novo login.',
    );
  }
  return issued;
}

Future<Json> verifyChatGptIdentity(
  String token,
  Json jwks,
  String clientId, {
  String? nonce,
  String? subject,
}) async {
  try {
    if (token.length > 65536) throw const FormatException();
    final keys = JsonWebKeyStore()..addKeySet(JsonWebKeySet.fromJson(jwks));
    final jwt = await JsonWebToken.decodeAndVerify(
      token,
      keys,
      allowedArguments: ['RS256'],
    );
    final c = jwt.claims;
    final now = DateTime.now();
    if (c['iss'] != _issuer ||
        c.subject == null ||
        c.subject!.isEmpty ||
        c.expiry == null ||
        !c.expiry!.isAfter(now) ||
        c.audience?.contains(clientId) != true ||
        (c.audience!.length > 1 && c['azp'] != clientId) ||
        (c['azp'] != null && c['azp'] != clientId) ||
        (c.notBefore != null && c.notBefore!.isAfter(now)) ||
        (c.issuedAt != null &&
            c.issuedAt!.isAfter(now.add(const Duration(minutes: 1)))) ||
        (nonce != null && c['nonce'] != nonce) ||
        (subject != null && c.subject != subject)) {
      throw const FormatException();
    }
    return {
      'subject': c.subject,
      'email': c['email'] is String ? c['email'] : null,
    };
  } catch (_) {
    throw const AiFailure(
      'Identidade do login não pôde ser validada. Confira relógio do aparelho e tente novamente.',
    );
  }
}

class ChatGptAuth {
  static final instance = ChatGptAuth();
  final FlutterSecureStorage storage;
  final Dio http;
  final Future<bool> Function(Uri) openBrowser;
  ChatGptAuth({
    this.storage = const FlutterSecureStorage(),
    Dio? client,
    Future<bool> Function(Uri)? browser,
  }) : http =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 20),
               followRedirects: false,
             ),
           ),
       openBrowser =
           browser ??
           ((url) => launchUrl(url, mode: LaunchMode.externalApplication));
  Future<void> _queue = Future.value();
  CancelToken? _login;
  final Map<String, Set<CancelToken>> _requests = {};

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<Json> _read() async =>
      jsonDecode(await storage.read(key: 'chatgpt.accounts') ?? '{}') as Json;
  Future<void> _write(Json accounts) =>
      storage.write(key: 'chatgpt.accounts', value: jsonEncode(accounts));
  Future<List<Json>> accounts() async => (await _read()).entries.map((e) {
    final a = e.value as Json;
    return <String, dynamic>{
      'id': e.key,
      'email': a['email'],
      'connected': a['access_token'] != null,
      'enabled':
          (a['scopes'] as List?)?.contains('chatgpt.tokens.use.direct') == true,
    };
  }).toList();

  Future<String> _host() async {
    final old = await storage.read(key: 'chatgpt.host');
    if (old != null) return old;
    final b = List.generate(16, (_) => Random.secure().nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    final host =
        'urn:uuid:${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
    await storage.write(key: 'chatgpt.host', value: host);
    return host;
  }

  Future<Json> _identity(
    String token,
    String clientId, {
    String? nonce,
    String? subject,
    CancelToken? cancel,
  }) async {
    final result = await http.get(
      '$_issuer/.well-known/jwks.json',
      cancelToken: cancel,
    );
    return verifyChatGptIdentity(
      token,
      Map<String, dynamic>.from(result.data as Map),
      clientId,
      nonce: nonce,
      subject: subject,
    );
  }

  Json _credentials(
    Json response,
    Json identity,
    String clientId, {
    Json? old,
  }) {
    final access = response['access_token'];
    final refresh = response['refresh_token'] ?? old?['refresh_token'];
    final expiry = response['expires_in'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        response['token_type']?.toString().toLowerCase() != 'bearer' ||
        expiry is! num ||
        !expiry.isFinite ||
        expiry <= 0 ||
        expiry > 31536000 ||
        (response['scope'] != null && response['scope'] is! String)) {
      throw const AiFailure(
        'Resposta de autenticação incompleta. Entre novamente.',
      );
    }
    return {
      ...?old,
      ...identity,
      'client_id': clientId,
      'access_token': access,
      'refresh_token': refresh,
      'id_token': response['id_token'] ?? old?['id_token'],
      'expires_at': DateTime.now()
          .add(Duration(seconds: expiry.toInt()))
          .toUtc()
          .toIso8601String(),
      'scopes': response['scope'] is String
          ? (response['scope'] as String).split(' ')
          : old?['scopes'] ?? <String>[],
    };
  }

  Future<String> signIn({
    String? accountId,
    required CancelToken cancel,
  }) async {
    if (_login != null) throw const AiFailure('Já existe login em andamento.');
    _login = cancel;
    try {
      return await _exclusive(() async {
        final accounts = await _read();
        final old = accountId == null ? null : accounts[accountId] as Json?;
        if (accountId != null && old == null) {
          throw const AiFailure('Conta não encontrada.');
        }
        final clientId = old?['client_id'] as String?;
        final host = await _host();
        if (cancel.isCancelled) throw const AiFailure('Login cancelado.');
        final server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
          shared: false,
        );
        final redirect = 'http://127.0.0.1:${server.port}/auth/callback';
        final state = oauthRandom(),
            nonce = oauthRandom(),
            verifier = oauthRandom();
        final callback = Completer<Uri>();
        final subscription = server.listen((request) async {
          request.response.headers.set('Cache-Control', 'no-store');
          request.response.headers.set(
            'Content-Security-Policy',
            "default-src 'none'; frame-ancestors 'none'",
          );
          request.response.headers.contentType = ContentType.text;
          if (request.method != 'GET' ||
              request.uri.path != '/auth/callback' ||
              request.headers.value(HttpHeaders.hostHeader) !=
                  '127.0.0.1:${server.port}' ||
              request.uri.toString().length > 16384) {
            request.response.statusCode = 404;
          } else {
            try {
              validateOAuthCallback(request.uri, state, clientId);
              if (!callback.isCompleted) callback.complete(request.uri);
              request.response.write(
                'Retorno recebido. Volte ao AI Fitness para conferir o login.',
              );
            } catch (e) {
              request.response.statusCode = 400;
              request.response.write('Retorno recusado. Volte ao AI Fitness.');
              if (request.uri.queryParameters['state'] == state &&
                  !callback.isCompleted) {
                callback.completeError(e);
              }
            }
          }
          await request.response.close();
        });
        try {
          final url = Uri.parse('$_issuer/api/accounts/authorize').replace(
            queryParameters: {
              'client_id': clientId ?? 'dynamic_agent_client',
              if (clientId == null) 'agent_name_hint': 'AI Fitness',
              'ext_agent_host_id': host,
              if (old?['id_token'] is String)
                'id_token_hint': old!['id_token'] as String,
              if (old?['email'] is String)
                'login_hint': old!['email'] as String,
              if (old != null &&
                  (old['scopes'] as List?)?.contains(
                        'chatgpt.tokens.use.direct',
                      ) !=
                      true)
                'prompt': 'consent',
              'response_type': 'code',
              'redirect_uri': redirect,
              'scope': _scopes,
              'resource': _resource,
              'state': state,
              'nonce': nonce,
              'code_challenge_method': 'S256',
              'code_challenge': pkceChallenge(verifier),
            },
          );
          // Attach handlers before opening browser; cancellation never leaks callback URL.
          final waiting =
              Future.any<Uri>([
                callback.future,
                cancel.whenCancel.then<Uri>(
                  (_) => throw const AiFailure('Login cancelado.'),
                ),
              ]).timeout(
                const Duration(minutes: 5),
                onTimeout: () => throw const AiFailure(
                  'Tempo de login esgotado. Inicie novamente.',
                ),
              );
          // Browser launch may still be pending when cancellation completes.
          unawaited(
            waiting.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
          );
          bool opened;
          try {
            opened = await openBrowser(url);
          } catch (_) {
            opened = false;
          }
          if (!opened) {
            cancel.cancel();
            // Consume cancellation before returning to prevent unhandled future errors.
            try {
              await waiting;
            } catch (_) {}
            throw const AiFailure(
              'Não foi possível abrir navegador para login.',
            );
          }
          final uri = await waiting;
          final issued = validateOAuthCallback(uri, state, clientId);
          final result = await http.post(
            '$_issuer/api/accounts/oauth/token',
            data: {
              'grant_type': 'authorization_code',
              'client_id': issued,
              'code': uri.queryParameters['code'],
              'code_verifier': verifier,
              'redirect_uri': redirect,
              'resource': _resource,
            },
            options: Options(contentType: Headers.formUrlEncodedContentType),
            cancelToken: cancel,
          );
          final tokens = Map<String, dynamic>.from(result.data as Map);
          final identity = await _identity(
            tokens['id_token'] as String,
            issued,
            nonce: nonce,
            subject: old?['subject'] as String?,
            cancel: cancel,
          );
          if (cancel.isCancelled) throw const AiFailure('Login cancelado.');
          final id = accountId ?? issued;
          final existing = accounts[id] as Json?;
          if (existing != null && existing['subject'] != identity['subject']) {
            throw const AiFailure(
              'Registro pertence a outra identidade. Nenhuma sessão foi substituída.',
            );
          }
          accounts[id] = _credentials(tokens, identity, issued, old: old);
          await _write(accounts);
          return id;
        } finally {
          await subscription.cancel();
          await server.close(force: true);
        }
      });
    } on AiFailure {
      rethrow;
    } catch (_) {
      throw const AiFailure(
        'Login não concluído. Confira conexão e autorização no navegador. Nenhuma chave API substitui esse login.',
      );
    } finally {
      _login = null;
    }
  }

  Future<String> accessToken(String accountId) => _exclusive(() async {
    final accounts = await _read();
    var a = accounts[accountId] as Json?;
    if (a == null || a['access_token'] == null) {
      throw const AiFailure(
        'Entre com ChatGPT nesta configuração antes de conversar.',
      );
    }
    if ((a['scopes'] as List?)?.contains('chatgpt.tokens.use.direct') != true) {
      throw const AiFailure(
        'Conta conectada sem autorização para usar plano. Abra configuração e entre novamente para autorizar.',
      );
    }
    if (DateTime.parse(a['expires_at'] as String)
        .isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return a['access_token'] as String;
    }
    try {
      final result = await http.post(
        '$_issuer/api/accounts/oauth/token',
        data: {
          'grant_type': 'refresh_token',
          'client_id': a['client_id'],
          'refresh_token': a['refresh_token'],
          'resource': _resource,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final tokens = Map<String, dynamic>.from(result.data as Map);
      final identity = tokens['id_token'] is String
          ? await _identity(
              tokens['id_token'] as String,
              a['client_id'] as String,
              subject: a['subject'] as String,
            )
          : <String, dynamic>{'subject': a['subject'], 'email': a['email']};
      a = _credentials(tokens, identity, a['client_id'] as String, old: a);
      accounts[accountId] = a;
      await _write(accounts);
      if ((a['scopes'] as List).contains('chatgpt.tokens.use.direct') != true) {
        throw const AiFailure(
          'Autorização de uso do plano ausente. Entre novamente.',
        );
      }
      return a['access_token'] as String;
    } on DioException catch (e) {
      final data = e.response?.data;
      final code = data is Map ? data['error'] : null;
      if (code == 'invalid_client') {
        throw const AiFailure(
          'OpenAI recusou registro deste cliente ChatGPT. Configuração de login precisa ser revista; repetir envio não resolve.',
        );
      }
      if (const [
        'invalid_grant',
        'invalid_refresh_token',
        'token_expired',
        'refresh_token_expired',
        'refresh_token_invalidated',
        'refresh_token_reused',
      ].contains(code)) {
        accounts[accountId] = _withoutTokens(a!);
        await _write(accounts);
        throw const AiFailure(
          'Sessão ChatGPT expirou ou foi revogada. Entre novamente.',
        );
      }
      throw const AiFailure(
        'Não foi possível renovar sessão ChatGPT. Credenciais preservadas; tente mais tarde.',
      );
    }
  });

  Json _withoutTokens(Json a) => {...a}
    ..removeWhere(
      (k, _) => [
        'access_token',
        'refresh_token',
        'id_token',
        'expires_at',
        'scopes',
      ].contains(k),
    );
  CancelToken startRequest(String id, CancelToken? caller) {
    final token = CancelToken();
    (_requests[id] ??= {}).add(token);
    if (caller != null) {
      if (caller.isCancelled) token.cancel();
      caller.whenCancel.then((_) => token.cancel());
    }
    return token;
  }

  void endRequest(String id, CancelToken token) => _requests[id]?.remove(token);

  Future<bool> signOut(String id) {
    _login?.cancel();
    for (final t in _requests[id] ?? <CancelToken>{}) {
      t.cancel();
    }
    return _exclusive(() async {
      final accounts = await _read();
      final a = accounts[id] as Json?;
      if (a == null) return true;
      var revoked = a['refresh_token'] == null;
      if (!revoked) {
        try {
          final metadata = await http.get(
            '$_issuer/.well-known/openid-configuration',
          );
          final endpoint = Uri.parse(
            (metadata.data as Map)['revocation_endpoint'] as String,
          );
          if (endpoint.scheme != 'https' ||
              endpoint.host != 'auth.openai.com' ||
              endpoint.port != 443 ||
              endpoint.hasQuery ||
              endpoint.hasFragment ||
              endpoint.userInfo.isNotEmpty) {
            throw const FormatException();
          }
          final result = await http.postUri(
            endpoint,
            data: {
              'token': a['refresh_token'],
              'token_type_hint': 'refresh_token',
              'client_id': a['client_id'],
            },
            options: Options(contentType: Headers.formUrlEncodedContentType),
          );
          revoked = result.statusCode == 200;
        } catch (_) {
          revoked = false;
        }
      }
      accounts[id] = _withoutTokens(a);
      await _write(accounts);
      return revoked;
    });
  }

  Future<bool> signOutAll() async {
    _login?.cancel();
    var confirmed = true;
    for (final a in await accounts()) {
      if (!await signOut(a['id'] as String)) confirmed = false;
    }
    return confirmed;
  }
}

String chatGptFailure(Object? code) => switch (code) {
  'subscription_sharing_usage_limit_exceeded' => 'Limite autorizado para este app ou plano ChatGPT atingido. Confira https://chatgpt.com/settings/usage. Nenhuma cobrança por chave API foi usada.',
  'subscription_sharing_user_not_eligible' => 'OpenAI não habilitou uso do plano para esta conta ou workspace. Confira elegibilidade; não há troca automática para API paga.',
  'subscription_sharing_usage_unavailable' ||
  'subscription_sharing_user_unavailable' => 'Disponibilidade do plano ChatGPT temporariamente indisponível. Sessão preservada; tente mais tarde.',
  'subscription_sharing_unsupported_capability' => 'Modelo ou recurso não permitido neste acesso ChatGPT. Selecione modelo do catálogo da conta.',
  'subscription_sharing_route_not_supported' ||
  'chatpass_v2_scope_not_authorized' ||
  'chatpass_v2_invalid_authorization_context' =>
    'OpenAI recusou rota ou autorização de uso do plano para esta integração.',
  'subscription_sharing_invalid_user' => 'OpenAI não validou sessão ChatGPT. Confira conta e entre novamente se acesso tiver sido revogado.',
  _ => 'Solicitação ChatGPT falhou ou ficou incompleta. Nenhuma cobrança por chave API foi usada.',
};

class ChatGptProvider implements AiProvider {
  final AiConfig config;
  final ChatGptAuth auth;
  final Dio http;
  ChatGptProvider(this.config, {ChatGptAuth? authentication, Dio? client})
    : auth = authentication ?? ChatGptAuth.instance,
      http = client ?? Dio() {
    if (config.type != chatGptType ||
        config.authId == null ||
        config.baseUrl != _resource) {
      throw const AiFailure('Configuração ChatGPT inválida.');
    }
    http.options = BaseOptions(
      baseUrl: _resource,
      followRedirects: false,
      connectTimeout: Duration(seconds: config.timeout),
      receiveTimeout: Duration(seconds: config.timeout),
      sendTimeout: Duration(seconds: config.timeout),
    );
  }

  @override
  Future<List<String>> models({CancelToken? cancel}) async {
    final token = auth.startRequest(config.authId!, cancel);
    try {
      final access = await auth.accessToken(config.authId!);
      final response = await http.get(
        '/models',
        options: Options(headers: {'Authorization': 'Bearer $access'}),
        cancelToken: token,
      );
      final data = response.data;
      if (data is! Map || data['models'] is! List) {
        throw const AiFailure('Catálogo da conta ChatGPT inválido.');
      }
      return (data['models'] as List)
          .whereType<Map>()
          .where((m) => m['visibility'] == 'list')
          .take(2000)
          .map((m) => text(m['slug'], max: 200))
          .toList();
    } on DioException catch (e) {
      throw await _requestError(e);
    } finally {
      auth.endRequest(config.authId!, token);
    }
  }

  Future<AiFailure> _requestError(DioException e) async {
    if (CancelToken.isCancel(e)) return const AiFailure('Operação cancelada.');
    Object? data = e.response?.data;
    if (data is ResponseBody) {
      final body = data;
      try {
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in body.stream.timeout(
          const Duration(seconds: 10),
        )) {
          if (bytes.length + chunk.length > 65536) break;
          bytes.add(chunk);
        }
        data = jsonDecode(utf8.decode(bytes.takeBytes()));
      } catch (_) {
        data = null;
      }
    }
    final error = data is Map ? data['error'] : null;
    final code = error is Map ? error['code'] : null;
    final known =
        code is String &&
        (code.startsWith('subscription_sharing_') ||
            code.startsWith('chatpass_v2_'));
    final message = known
        ? chatGptFailure(code)
        : switch (e.response?.statusCode) {
            401 => 'Sessão ChatGPT não aceita. Abra configuração e entre novamente; confira autorização de uso do plano.',
            403 => 'OpenAI recusou acesso ChatGPT para esta conta, região ou integração. Não há troca automática para API paga.',
            429 => 'OpenAI retornou HTTP 429 para acesso ChatGPT sem causa reconhecida. Confira limites do app em https://chatgpt.com/settings/usage.',
            503 => 'Rota ChatGPT indisponível ou ainda não habilitada. Sessão preservada; tente mais tarde.',
            _ => 'Falha na conexão ChatGPT. Confira rede e disponibilidade da integração.',
          };
    final requestId = e.response?.headers.map['x-request-id']?.firstOrNull;
    final safeId =
        requestId != null &&
        RegExp(r'^req_[A-Za-z0-9_-]{1,100}$').hasMatch(requestId);
    return AiFailure(
      '$message${safeId ? '\nID da solicitação: $requestId' : ''}',
    );
  }

  @override
  Stream<String> generate(
    List<Json> messages, {
    String? system,
    Uint8List? image,
    CancelToken? cancel,
  }) async* {
    if (messages.isEmpty ||
        messages.length > 40 ||
        messages.any(
          (m) =>
              !['user', 'assistant'].contains(m['role']) ||
              m['content'] is! String,
        )) {
      throw const AiFailure('Use até 40 mensagens de texto por envio.');
    }
    if (image != null && (!config.images || image.length > 5 * 1024 * 1024)) {
      throw const AiFailure('Imagem não suportada ou maior que 5 MB.');
    }
    final input = messages
        .map(
          (m) => <String, dynamic>{'role': m['role'], 'content': m['content']},
        )
        .toList();
    if (image != null) {
      input.last['content'] = [
        {'type': 'input_text', 'text': messages.last['content']},
        {
          'type': 'input_image',
          'image_url': 'data:image/jpeg;base64,${base64Encode(image)}',
        },
      ];
    }
    final token = auth.startRequest(config.authId!, cancel);
    try {
      final access = await auth.accessToken(config.authId!);
      final response = await http.post(
        '/responses',
        data: {
          'model': config.model,
          'input': input,
          'store': false,
          'stream': true,
          'instructions': ?system,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Authorization': 'Bearer $access'},
        ),
        cancelToken: token,
      );
      final body = response.data;
      if (body is! ResponseBody) {
        throw const AiFailure('Streaming ChatGPT inválido.');
      }
      var size = 0;
      var completed = false;
      await for (final line
          in body.stream
              .map((chunk) {
                size += chunk.length;
                if (size > 4 * 1024 * 1024) {
                  token.cancel();
                  throw const AiFailure('Resposta excedeu limite de 4 MB.');
                }
                return chunk;
              })
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final raw = line.substring(5).trim();
        if (raw.isEmpty || raw == '[DONE]') continue;
        final event = jsonDecode(raw);
        if (event is! Map) throw const AiFailure('Evento ChatGPT inválido.');
        switch (event['type']) {
          case 'response.output_text.delta':
            if (event['delta'] is! String) {
              throw const AiFailure('Texto ChatGPT inválido.');
            }
            yield event['delta'] as String;
          case 'response.completed':
            if (event['response'] is! Map ||
                event['response']['status'] != 'completed') {
              throw const AiFailure('Resposta ChatGPT não concluída.');
            }
            completed = true;
          case 'response.failed':
            final r = event['response'];
            final e = r is Map ? r['error'] : null;
            throw AiFailure(chatGptFailure(e is Map ? e['code'] : null));
          case 'error':
            throw AiFailure(chatGptFailure(event['code']));
          case 'response.incomplete':
            throw const AiFailure(
              'Resposta ChatGPT incompleta. Texto parcial não confirma conclusão.',
            );
        }
        if (completed) break;
      }
      if (!completed) {
        throw const AiFailure(
          'Conexão interrompida antes da conclusão da resposta ChatGPT.',
        );
      }
    } on DioException catch (e) {
      throw await _requestError(e);
    } on FormatException {
      throw const AiFailure('Evento ChatGPT malformado.');
    } finally {
      auth.endRequest(config.authId!, token);
    }
  }
}

Future<AiProvider> configuredProvider(AiConfig config) async =>
    config.type == chatGptType
    ? ChatGptProvider(config)
    : HttpAiProvider(config, await const KeyVault().read(config.id));
