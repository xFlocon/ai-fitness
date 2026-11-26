import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/ai.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';

const videoKeySlot = 'youtube-data-api';
final _exerciseTerm = RegExp(r'^[\p{L}\p{M}0-9 ()-]{1,120}$', unicode: true);
final _genericWords = RegExp(
  r'\b(de|da|do|das|dos|com|no|na|the|with|on|how|to|do|proper|form|exercise|tutorial|technique|como|fazer|tecnica|execucao)\b',
);
const _aliases = <String, String>{
  'dumbbells?': 'halter',
  'halteres': 'halter',
  'barbell': 'barra',
  'barra reta': 'barra',
  'inclined?|inclinada': 'inclinado',
  'declined?|declinada': 'declinado',
  'flat': 'reto',
  'bench press': 'supino',
  'shoulder press|overhead press': 'desenvolvimento',
  'lateral raises?': 'elevacao lateral',
  'lat pull ?downs?': 'puxada alta',
  'crunch(?:es)?': 'abdominal',
  'triceps push ?downs?': 'triceps polia',
  'biceps? curls?': 'rosca',
  'curls?': 'rosca',
  'hammer': 'martelo',
  'squats?': 'agachamento',
  'deadlifts?': 'terra',
  'levantamento terra': 'terra',
  'push ?ups?': 'flexao',
  'planks?': 'prancha',
  'leg press': 'legpress',
  'cables?': 'polia',
  'machines?': 'maquina',
  'seated|sentada': 'sentado',
  'standing|em pe': 'empe',
  'single arm': 'unilateral',
  'one arm': 'unilateral',
  'arms only|somente bracos|apenas bracos|so bracos': 'apenasbracos',
  'legs only|somente pernas|apenas pernas|so pernas': 'apenaspernas',
};
const _variants = {
  {'halter', 'barra', 'polia', 'maquina'},
  {'inclinado', 'declinado', 'reto'},
  {'sentado', 'empe'},
  {'martelo', 'concentrada', 'scott', 'inversa'},
  {'apenasbracos', 'apenaspernas'},
};

String _videoWords(String input) {
  var value = input.toLowerCase().replaceAll(
    RegExp(r'&(?:amp|quot|#39|lt|gt);'),
    ' ',
  );
  for (final (index, letter) in 'aeiouc'.split('').indexed) {
    value = value.replaceAll(
      RegExp(['[áàâãä]', '[éèêë]', '[íìîï]', '[óòôõö]', '[úùûü]', 'ç'][index]),
      letter,
    );
  }
  value = value.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  for (final entry in _aliases.entries) {
    value = value.replaceAll(RegExp('\\b(?:${entry.key})\\b'), entry.value);
  }
  return value
      .replaceAll(_genericWords, ' ')
      .replaceAll(RegExp(r' +'), ' ')
      .trim();
}

bool _unsuitableTitle(String title, String terms) {
  final candidate = _videoWords(title);
  if (RegExp(
    r'\b(top \d+|compilation|compilacao|full workout|treino completo|melhores exercicios|variations|variacoes)\b',
  ).hasMatch(candidate)) {
    return true;
  }
  final requested = _videoWords(terms).split(' ').toSet();
  final actual = candidate.split(' ').toSet();
  return _variants.any((group) {
    final needed = requested.intersection(group);
    return needed.isNotEmpty &&
        actual.intersection(group).difference(needed).isNotEmpty;
  });
}

int _videoMatch(String title, String query, String? name) {
  if (_unsuitableTitle(title, '$query ${name ?? ''}')) return 0;
  final candidate = _videoWords(title);
  final words = candidate.split(' ').toSet();
  final expected = [
    for (final term in [query, ?name]) _videoWords(term),
  ].where((term) => term.isNotEmpty);
  final requested = expected.expand((term) => term.split(' ')).toSet();
  for (final group in _variants) {
    final needed = requested.intersection(group);
    if (needed.isNotEmpty &&
        (!words.containsAll(needed) ||
            words.intersection(group).difference(needed).isNotEmpty)) {
      return 0;
    }
  }
  final matched = expected
      .where((term) => words.containsAll(term.split(' ')))
      .toList();
  if (matched.isEmpty) return 0;
  // A broad translation like "press" must not override a more specific exercise name.
  if (name != null &&
      _videoWords(name).contains(' ') &&
      matched.every((term) => !term.contains(' '))) {
    return 0;
  }
  return 1 +
      matched.length * 2 +
      (matched.any((term) => ' $candidate '.contains(' $term ')) ? 2 : 0) +
      (RegExp(
            r'\b(how to|como fazer|tutorial|proper form|execu[cç][aã]o|t[eé]cnica)\b',
            caseSensitive: false,
          ).hasMatch(title)
          ? 1
          : 0);
}

String exerciseVideoQuery(Object? suggested, String name) {
  final term = suggested is String ? suggested.trim() : '';
  if (_exerciseTerm.hasMatch(term)) return term;
  return name
      .replaceAll(RegExp(r'[^\p{L}\p{M}0-9 ()-]+', unicode: true), ' ')
      .trim();
}

String _retryVideoQuery(String query, String? name) {
  final movement = _videoWords('$query ${name ?? ''}');
  if (RegExp(r'\b(dead bug|inseto morto)\b').hasMatch(movement)) {
    return 'dead bug exercise';
  }
  if (RegExp(r'\b(marcha|marchar) lugar\b').hasMatch(movement)) {
    return 'marching in place exercise';
  }
  return '$query exercise';
}

// Search uses only exercise terms. AI-supplied links and domains never enter the player.
String youtubeSearchError(DioException error) {
  final payload = error.response?.data;
  final detail = payload is Map ? payload['error'] : null;
  final reasons = detail is Map ? detail['errors'] : null;
  final codes = reasons is List
      ? reasons.whereType<Map>().map((item) => item['reason']).toSet()
      : const <Object?>{};
  if (codes.any(const {'quotaExceeded', 'dailyLimitExceeded'}.contains)) {
    return 'Cota diária do YouTube esgotada. Confira a cota no Google Cloud ou aguarde a renovação.';
  }
  if (codes.any(
    const {'keyInvalid', 'accessNotConfigured', 'ipRefererBlocked'}.contains,
  )) {
    return 'YouTube recusou a chave ou o acesso à API. Confira a chave, as restrições e se a YouTube Data API v3 está ativa.';
  }
  return switch (error.response?.statusCode) {
    429 => 'YouTube limitou as buscas temporariamente. Aguarde antes de tentar novamente.',
    401 || 403 => 'YouTube recusou a busca. Confira a chave e as permissões no Google Cloud.',
    final int status when status >= 500 => 'YouTube indisponível no momento.',
    final int status => 'YouTube recusou a busca (HTTP $status).',
    _ => 'Não foi possível conectar ao YouTube. Confira a conexão.',
  };
}

Future<List<String?>> findExerciseVideos(
  List<String> queries,
  String key, {
  List<String>? names,
  List<String>? portugueseQueries,
  Future<List<String?>> Function(List<List<Json>>)? choose,
  CancelToken? cancel,
  Dio? client,
}) async {
  final dio =
      client ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          followRedirects: false,
        ),
      );
  Future<List<Json>> get(String endpoint, Json parameters) async {
    try {
      final response = await dio.get<Json>(
        'https://www.googleapis.com/youtube/v3/$endpoint',
        queryParameters: parameters,
        options: Options(headers: {'X-Goog-Api-Key': key}),
        cancelToken: cancel,
      );
      return (response.data?['items'] as List? ?? [])
          .whereType<Json>()
          .toList();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw AiFailure(youtubeSearchError(e));
    }
  }

  try {
    final searchTerms = [
      for (final (i, query) in queries.indexed)
        {
          query.toLowerCase(): query,
          if (portugueseQueries?[i] case final String pt when pt.isNotEmpty)
            pt.toLowerCase(): pt,
        }.values.join('|'),
    ];
    // ponytail: review metadata, not video frames; leave uncertain exercises without a link.
    final candidates = await Future.wait(
      searchTerms.toSet().map((query) async {
        final hits = await get('search', {
          'part': 'id,snippet',
          'type': 'video',
          'q': query,
          'videoDuration': 'short',
          'videoEmbeddable': 'true',
          'safeSearch': 'strict',
          'maxResults': 12,
        });
        return MapEntry(query, {
          for (final hit in hits)
            if (hit
                case {
                  'id': {'videoId': final String id},
                  'snippet': final Json snippet,
                }
                when youtubeVideoId(id) == id)
              id: snippet,
        });
      }),
    );
    final byQuery = Map.fromEntries(candidates);
    final ranked = [
      for (final (i, query) in queries.indexed)
        (() {
          if (choose != null) return byQuery[searchTerms[i]]!.keys.toList();
          final matches = <({String id, int score, int order})>[];
          for (final (order, entry)
              in byQuery[searchTerms[i]]!.entries.indexed) {
            final score = _videoMatch(
              '${entry.value['title'] ?? ''}',
              query,
              names?[i],
            );
            if (score > 0) {
              matches.add((id: entry.key, score: score, order: order));
            }
          }
          matches.sort(
            (a, b) => a.score == b.score
                ? a.order.compareTo(b.order)
                : b.score.compareTo(a.score),
          );
          return matches.map((m) => m.id).take(2).toList();
        })(),
    ];
    final ids = ranked.expand((ids) => ids).toSet().toList();
    if (ids.isEmpty) return List.filled(queries.length, null);
    final videos = (await Future.wait([
      for (var i = 0; i < ids.length; i += 50)
        get('videos', {
          'part': 'status,contentDetails',
          'id': ids.skip(i).take(50).join(','),
        }),
    ])).expand((batch) => batch);
    final durations = <String, int>{};
    final usable = videos
        .where((video) {
          final status = video['status'] as Map?;
          final duration = (video['contentDetails'] as Map?)?['duration'];
          final match = duration is String
              ? RegExp(r'^PT(?:(\d+)M)?(?:(\d+)S)?$').firstMatch(duration)
              : null;
          if (match == null) return false;
          final seconds =
              60 * int.parse(match[1] ?? '0') + int.parse(match[2] ?? '0');
          if (video['id'] is String) durations[video['id'] as String] = seconds;
          return status?['embeddable'] == true &&
              status?['privacyStatus'] == 'public' &&
              seconds > 0 &&
              seconds < 240;
        })
        .map((video) => video['id'])
        .toSet();
    if (choose == null) {
      return ranked
          .map((ids) => ids.where(usable.contains).firstOrNull)
          .toList();
    }
    final options = [
      for (final (i, ids) in ranked.indexed)
        [
          for (final id in ids.where(usable.contains))
            <String, dynamic>{
              'id': id,
              'seconds': durations[id],
              'title': _videoMetadata(
                byQuery[searchTerms[i]]![id]!['title'],
                160,
              ),
              'description': _videoMetadata(
                byQuery[searchTerms[i]]![id]!['description'],
                80,
              ),
            },
        ],
    ];
    bool unsuitable(int i, Json video) => _unsuitableTitle(
      video['title'] as String,
      '${queries[i]} ${names?[i] ?? ''} ${portugueseQueries?[i] ?? ''}',
    );
    for (final (i, row) in options.indexed) {
      row.removeWhere((v) => unsuitable(i, v));
    }
    Future<List<List<Json>>> extra(List<int> indices) async {
      final expanded = List.generate(queries.length, (_) => <Json>[]);
      if (indices.isEmpty) return expanded;
      await findExerciseVideos(
        [for (final i in indices) _retryVideoQuery(queries[i], names?[i])],
        key,
        client: dio,
        cancel: cancel,
        choose: (rows) async {
          for (final (j, i) in indices.indexed) {
            final seen = options[i].map((v) => v['id']).toSet();
            expanded[i] = rows[j]
                .where((v) => !unsuitable(i, v) && seen.add(v['id']))
                .toList();
          }
          return [];
        },
      );
      return expanded;
    }

    // ponytail: one extra search per exercise, not open-ended pagination.
    final toppedUp = [
      if (portugueseQueries != null)
        for (final (i, row) in options.indexed)
          if (row.length < 4) i,
    ];
    final supplements = await extra(toppedUp);
    for (final (i, row) in options.indexed) {
      row.addAll(supplements[i]);
      int score(Json v) =>
          _videoMatch(v['title'] as String, queries[i], names?[i]);
      row.sort((a, b) {
        final relevance = score(b).compareTo(score(a));
        return relevance != 0
            ? relevance
            : (a['seconds'] as int).compareTo(b['seconds'] as int);
      });
      if (row.length > 4) row.removeRange(4, row.length);
    }
    final chosen = options.every((row) => row.isEmpty)
        ? const <String?>[]
        : await choose(options);
    final results = [
      for (final (i, row) in options.indexed)
        if (i < chosen.length && row.any((video) => video['id'] == chosen[i]))
          chosen[i]
        else
          null,
    ];
    if (portugueseQueries != null && results.contains(null)) {
      final retry = [
        for (final (i, id) in results.indexed)
          if (id == null && !toppedUp.contains(i)) i,
      ];
      final rows = await extra(retry);
      if (rows.any((row) => row.isNotEmpty)) {
        final picks = await choose(rows);
        for (final i in retry) {
          if (i < picks.length && rows[i].any((v) => v['id'] == picks[i])) {
            results[i] = picks[i];
          }
        }
      }
    }
    return results;
  } finally {
    if (client == null) dio.close(force: true);
  }
}

String _videoMetadata(Object? value, int limit) =>
    value is String ? String.fromCharCodes(value.runes.take(limit)) : '';

Future<void> configureExerciseVideos(BuildContext context) async {
  const vault = KeyVault();
  try {
    final configured = (await vault.read(videoKeySlot)).isNotEmpty;
    if (!context.mounted) return;
    final key = await ask(
      context,
      configured
          ? 'Nova chave do YouTube (vazio remove)'
          : 'Chave da YouTube Data API v3',
      secret: true,
    );
    if (key == null || !context.mounted) return;
    await vault.write(videoKeySlot, text(key, max: 200, optional: true));
    if (context.mounted) {
      notice(
        context,
        key.trim().isEmpty
            ? 'Busca automática desativada.'
            : 'Chave do YouTube salva.',
      );
    }
  } catch (_) {
    if (context.mounted) {
      notice(context, 'Não foi possível configurar a chave do YouTube.');
    }
  }
}

class ExerciseVideo extends StatefulWidget {
  final String id;
  ExerciseVideo({required this.id}) : super(key: ValueKey(id));

  @override
  State<ExerciseVideo> createState() => _ExerciseVideoState();
}

class _ExerciseVideoState extends State<ExerciseVideo> {
  WebViewController? player;
  bool failed = false, loading = false;

  Future<void> load() async {
    setState(() {
      failed = false;
      loading = true;
    });
    final embed = Uri.https('www.youtube-nocookie.com', '/embed/${widget.id}', {
      'playsinline': '1',
    });
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              !request.isMainFrame || request.url == embed.toString()
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => failed = true);
            }
          },
        ),
      );
      await controller.loadRequest(
        embed,
        headers: {'Referer': 'https://br.com.aifitness.ai_fitness/'},
      );
      if (mounted) setState(() => player = controller);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (player != null && !failed)
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 200),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: WebViewWidget(controller: player!),
          ),
        )
      else
        OutlinedButton.icon(
          onPressed: loading ? null : load,
          icon: const Icon(Icons.play_circle_outline),
          label: Text(
            loading
                ? 'Carregando vídeo…'
                : failed
                ? 'Tentar vídeo novamente'
                : 'Carregar vídeo no app',
          ),
        ),
      if (player == null && !failed)
        const Text('Ao carregar, seu aparelho se conecta ao YouTube.'),
      if (failed) const Text('Vídeo indisponível no player.'),
      TextButton(
        onPressed: () async {
          try {
            if (await launchUrl(
              Uri.https('www.youtube.com', '/watch', {'v': widget.id}),
              mode: LaunchMode.externalApplication,
            )) {
              return;
            }
          } catch (_) {}
          if (context.mounted) {
            notice(context, 'Não foi possível abrir o YouTube.');
          }
        },
        child: const Text('Abrir no YouTube'),
      ),
    ],
  );
}
