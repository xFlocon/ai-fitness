import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/models.dart';
import 'exercise_video.dart';

const _root = 'assets/exercises';
const _media = '$_root/media';
const onlineGifBase =
    'https://raw.githubusercontent.com/xFlocon/ai-fitness/6d09ad7040bf3fab1b47748a26480bf588bdfd50/';
const _commonsGifBase =
    'https://raw.githubusercontent.com/xFlocon/ai-fitness/b8004a71aa3085b3125a70a85e875a9545a00b1f/';
Map<String, Json>? _loadedCatalog;
Future<Map<String, Json>>? _loadingCatalog;
Future<Map<String, Json>> loadExerciseCatalog() {
  if (_loadedCatalog case final Map<String, Json> loaded) {
    return SynchronousFuture(loaded);
  }
  return _loadingCatalog ??= _loadCatalog();
}

Future<Map<String, Json>> _loadCatalog() async {
  final raw = await rootBundle.loadString('$_root/catalog.json');
  final online = jsonDecode(
    await rootBundle.loadString('$_root/online-gifs.json'),
  ) as Json;
  final commons = jsonDecode(
    await rootBundle.loadString('$_root/commons-online.json'),
  ) as List;
  return _loadedCatalog = {
    for (final e in (jsonDecode(raw) as List).cast<Json>())
      e['id'] as String: online[e['id']] is Json
          ? {
              ...e,
              ...online[e['id']] as Json,
              'kind': e['kind'] ?? 'online-gif',
              if (e['id'] == 'flow-1004')
                'notes': [
                  'Pise no elástico e segure as pontas junto aos ombros antes de agachar.',
                ],
            }
          : e,
    for (final e in commons.cast<Json>()) e['id'] as String: e,
  };
}

String catalogName(Json e) => (e['pt'] ?? e['en']) as String;

String catalogMuscle(Json e) => e['target'] == 'glutes'
    ? 'Glúteos'
    : _focusTags.entries
              .where((tag) => tag.value.contains(e['group']))
              .map((tag) => tag.key)
              .firstOrNull ??
          'Corpo inteiro';

const equipmentLabels = {
  'body weight': 'peso corporal',
  'wall': 'parede',
  'chair': 'cadeira firme',
  'step': 'degrau com apoio',
  'dumbbell': 'halteres',
  'bench': 'banco',
  'barbell': 'barra',
  'cable': 'polia',
  'band': 'faixa elástica',
  'resistance band': 'elástico de resistência',
  'leverage machine': 'máquina',
  'smith machine': 'máquina Smith',
  'stability ball': 'bola suíça',
  'medicine ball': 'bola medicinal',
  'ez barbell': 'barra W',
  'dip bars': 'paralelas',
  'pull-up bar': 'barra fixa',
  'plate': 'anilha',
  'roller': 'rolo',
  'massage ball': 'bola de massagem',
  'anchor': 'apoio para os pés',
  'kettlebell': 'kettlebell',
  'sled machine': 'máquina de trenó / leg press',
  'assisted': 'máquina assistida',
  'rope': 'corda',
  'bosu ball': 'BOSU',
  'wheel roller': 'roda abdominal',
  'stationary bike': 'bicicleta ergométrica',
  'elliptical machine': 'elíptico',
  'weighted': 'carga extra',
};

String catalogGear(Json e) =>
    (e['gear'] as List).map((g) => equipmentLabels[g] ?? g).join(', ');

String _normalized(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[áàâãä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôõö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll('ç', 'c');

// ponytail: glossário de nomes comuns, não tradução automática de variantes.
const _searchAliases = {
  r'bench press|chest press|supino': 'supino',
  r'pull ?ups?|barra fixa': 'barrafixa',
  r'push ?ups?|flexao de bracos|flexoes de bracos|flexao|flexoes': 'flexao',
  r'glute bridge|ponte de gluteos': 'ponte gluteos',
  r'hip thrust|elevacao pelvica': 'elevacao pelvica',
  r'deadlift|levantamento terra': 'terra',
  r'squats?|agachamentos?': 'agachamento',
  r'lunges?|avancos?|passadas?': 'avanco',
  r'rows?|remadas?': 'remada',
  r'curls?|roscas?': 'rosca',
  r'crunch(?:es)?|abdominais|abdominal': 'abdominal',
  r'skier jacks?|polichinelo alternado(?: frente e tras)?':
      'polichinelo alternado',
  r'jumping jacks?|polichinelos?': 'polichinelo',
  r'mountain climbers?|escaladores?|alpinistas?': 'escalador',
  r'heel slides?|deslizamento de calcanhar': 'deslizamento calcanhar',
  r'leg raises?|elevacao de pernas': 'elevacao pernas',
  r'calf raises?|elevacao de panturrilhas': 'elevacao panturrilhas',
  r'leg extensions?|cadeira extensora': 'cadeira extensora',
  r'lying leg curls?|mesa flexora': 'mesa flexora',
  r'lat pull ?downs?|puxada alta': 'puxada alta',
  r'shoulder press|overhead press|desenvolvimento': 'desenvolvimento',
  r'lateral raises?|elevacao lateral': 'elevacao lateral',
  r'body ?weight|peso corporal': 'pesocorporal',
  r'dumbbells?|halteres?': 'halter',
  r'barbells?|barra': 'barra',
  r'kettlebells?': 'kettlebell',
  r'cables?|polias?': 'polia',
  r'resistance bands?|bands?|faixa elastica|elasticos?': 'elastico',
  r'benches|bench|bancos?': 'banco',
  r'incline[d]?|inclina(?:do|da)': 'inclinado',
  r'decline[d]?|declina(?:do|da)': 'declinado',
  r'flat|ret[oa]': 'reto',
  r'close grip|pegada fechada': 'pegadafechada',
  r'wide grip|pegada aberta': 'pegadaaberta',
  r'front|frontal': 'frontal',
  r'alternating|alternad[oa]': 'alternado',
  r'seated|sitting|sentad[oa]': 'sentado',
  r'lying|deitad[oa]': 'deitado',
  r'standing|em pe': 'empe',
  r'wall|parede': 'parede',
  r'kneeling|on knees|ajoelhad[oa]|de joelhos': 'joelhos',
  r'one arm|single arm|um braco': 'umbraco',
  r'one leg|single leg|uma perna': 'umaperna',
  r'reverse|revers[oa]|invers[oa]': 'reverso',
};
final _searchPatterns = {
  for (final MapEntry(:key, :value) in _searchAliases.entries)
    RegExp('\\b(?:$key)\\b'): value,
};

Set<String> _searchWords(String text) {
  var clean = _normalized(text).replaceAll(RegExp('[^a-z0-9]+'), ' ');
  for (final MapEntry(:key, :value) in _searchPatterns.entries) {
    clean = clean.replaceAll(key, value);
  }
  const ignored = {
    'de',
    'do',
    'da',
    'das',
    'dos',
    'com',
    'para',
    'no',
    'na',
    'on',
    'the',
    'with',
    'and',
    'em',
    'e',
    'a',
    'o',
    's',
    'por',
  };
  return clean
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !ignored.contains(w))
      .toSet();
}

final _catalogSearch = Expando<Set<String>>();
Set<String> _exerciseWords(Json e) => _catalogSearch[e] ??= _searchWords(
  '${e['en']} ${e['pt'] ?? ''} ${catalogGear(e)} ${(e['gear'] as List).join(' ')}',
);

List<Json> searchExerciseCatalog(
  Iterable<Json> records,
  String query, {
  bool mediaOnly = false,
}) {
  final terms = _searchWords(query);
  return records
      .where(
        (e) =>
            (!mediaOnly || e['kind'] != null) &&
            terms.every(
              (term) => _exerciseWords(e).any((word) => word.startsWith(term)),
            ),
      )
      .toList();
}

const _focusTags = {
  'Braços': ['upper arms', 'lower arms'],
  'Peito': ['chest'],
  'Costas': ['back'],
  'Ombros': ['shoulders'],
  'Pernas': ['upper legs', 'lower legs'],
  'Glúteos': ['glutes'],
  'Abdômen': ['waist'],
  'Cardio': ['cardio'],
  'Mobilidade': ['mobility'],
};

List<Json> workoutCandidates(
  Iterable<Json> records,
  Set<String> focus,
  Set<String> gear,
  String request,
) {
  final tags = focus.expand((f) => _focusTags[f] ?? const <String>[]).toSet();
  final terms = _searchWords(request).where((word) => word.length >= 3).toSet();
  final ranked = <(Json, int)>[];
  for (final e in records) {
    if (!(e['gear'] as List).every(gear.contains)) continue;
    final labels = {
      e['group'],
      e['target'],
      e['pattern'],
      if (e['mobility'] == true) 'mobility',
    };
    if (tags.isNotEmpty &&
        !focus.contains('Corpo inteiro') &&
        !labels.any(tags.contains)) {
      continue;
    }
    final words = _exerciseWords(e);
    ranked.add((
      e,
      terms.where(words.contains).length * 8 +
          (verifiedMedia(e)
              ? 4
              : e['kind'] != null
              ? 2
              : 0) +
          (words.contains('inclinado') &&
                  !terms.contains('inclinado') &&
                  terms.contains('reto')
              ? -8
              : 0) +
          (words.contains('declinado') &&
                  !terms.contains('declinado') &&
                  terms.contains('reto')
              ? -8
              : 0),
    ));
  }
  ranked.sort((a, b) {
    final score = b.$2.compareTo(a.$2);
    return score == 0 ? '${a.$1['id']}'.compareTo('${b.$1['id']}') : score;
  });
  // ponytail: distribui por grupo; adicionar índice semântico só se busca textual não bastar.
  final groups = <Object?, List<Json>>{};
  for (final (e, _) in ranked) {
    groups.putIfAbsent(e['group'], () => []).add(e);
  }
  return [
    for (var i = 0; i < 24; i++)
      for (final group in groups.values)
        if (i < group.length) group[i],
  ].take(24).toList();
}

Json selectedCatalogExercise(Json proposal, Map<String, Json> offered) {
  final entry = offered[proposal['catalogId']];
  if (entry == null) {
    throw const FormatException(
      'A IA escolheu um exercício fora do catálogo filtrado. Tente novamente.',
    );
  }
  return {
    ...proposal,
    'catalogId': entry['id'],
    'videoQuery': entry['en'],
    'videoQueryPt': entry['pt'] ?? proposal['videoQueryPt'],
    'name': catalogName(entry),
  };
}

bool hasDemonstration(Json e, Map<String, Json> catalog) =>
    youtubeVideoId(e['videoId']) != null ||
    catalog[e['catalogId']]?['kind'] != null;

bool verifiedMedia(Json? entry) =>
    entry?['kind'] != null &&
    (entry!['kind'] != 'online-gif' || entry['reviewed'] == true);

Future<Json?> pickCatalogExercise(BuildContext context) async {
  final catalog = await loadExerciseCatalog();
  if (!context.mounted) return null;
  var query = '';
  var mediaOnly = true;
  return showDialog<Json>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, state) {
        final matches = searchExerciseCatalog(
          catalog.values,
          query,
          mediaOnly: mediaOnly,
        );
        return AlertDialog(
          title: const Text('Catálogo de exercícios'),
          content: SizedBox(
            width: 440,
            height: 440,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Buscar nome ou equipamento',
                  ),
                  onChanged: (value) => state(() => query = value),
                ),
                CheckboxListTile(
                  value: mediaOnly,
                  title: const Text('Somente com demonstração'),
                  onChanged: (value) => state(() => mediaOnly = value == true),
                ),
                Expanded(
                  child: matches.isEmpty
                      ? const Center(
                          child: Text('Nenhum exercício encontrado.'),
                        )
                      : ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (context, i) {
                            final e = matches[i];
                            return ListTile(
                              title: Text(catalogName(e)),
                              leading: e['still'] == null
                                  ? null
                                  : Image.asset(
                                      '$_media/${e['id']}.${e['still']}',
                                      width: 52,
                                      height: 42,
                                      fit: BoxFit.contain,
                                    ),
                              subtitle: Text(
                                '${catalogGear(e)} • ${e['kind'] == 'mp4'
                                    ? 'Vídeo'
                                    : e['kind'] == 'gif'
                                    ? 'GIF'
                                    : e['kind'] == 'image'
                                    ? 'Imagens'
                                    : e['kind'] == 'online-gif'
                                    ? e['reviewed'] == true
                                          ? 'GIF online'
                                          : 'Ilustração online não revisada'
                                    : 'Sem demonstração'}',
                              ),
                              onTap: () => Navigator.pop(context, e),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    ),
  );
}

class ExerciseDemonstration extends StatelessWidget {
  final Json exercise;
  const ExerciseDemonstration(this.exercise, {super.key});

  @override
  Widget build(BuildContext context) {
    if (youtubeVideoId(exercise['videoId']) case final String id) {
      return ExerciseVideo(id: id);
    }
    final id = exerciseCatalogId(exercise['catalogId']);
    const missing = Text('Sem demonstração. Adicione um link no editor.');
    if (id == null) return missing;
    return FutureBuilder(
      future: loadExerciseCatalog(),
      builder: (context, snapshot) {
        final entry = snapshot.data?[id];
        if (snapshot.connectionState == ConnectionState.waiting &&
            entry == null) {
          return const LinearProgressIndicator();
        }
        return entry?['kind'] == null
            ? missing
            : entry!['kind'] == 'online-gif'
            ? _OnlineGif(entry, key: ValueKey(id))
            : Column(
                children: [
                  _LocalDemonstration(entry, key: ValueKey(id)),
                  if (entry['sha256'] != null)
                    _OnlineGif(entry, key: ValueKey('$id-online')),
                ],
              );
      },
    );
  }
}

Future<Uint8List> _loadOnlineGif(Json entry, CancelToken cancel) async {
  const maxBytes = 256 * 1024;
  final id = entry['id'] as String;
  final hash = entry['sha256'] as String;
  final cache = await getTemporaryDirectory();
  final file = File('${cache.path}/$hash.gif');
  if (await file.exists() && await file.length() <= maxBytes) {
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() == hash) return bytes;
  }
  final dio = Dio(
    BaseOptions(
      followRedirects: false,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );
  try {
    final filename = entry['file'] as String?;
    final response = await dio.get<ResponseBody>(
      filename == null ? '$onlineGifBase$id.gif' : '$_commonsGifBase$filename',
      cancelToken: cancel,
      options: Options(responseType: ResponseType.stream),
    );
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.data!.stream) {
      if (chunk.length > maxBytes - bytes.length) throw const FormatException();
      bytes.add(chunk);
    }
    final gif = bytes.takeBytes();
    if (sha256.convert(gif).toString() != hash) throw const FormatException();
    try {
      await file.writeAsBytes(gif);
    } on FileSystemException {
      // Reprodução ainda funciona sem espaço para cache.
    }
    return gif;
  } finally {
    dio.close(force: true);
  }
}

class _OnlineGif extends StatefulWidget {
  final Json entry;
  const _OnlineGif(this.entry, {super.key});

  @override
  State<_OnlineGif> createState() => _OnlineGifState();
}

class _OnlineGifState extends State<_OnlineGif> {
  Future<Uint8List>? _gif;
  CancelToken? _cancel;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _gif,
    builder: (context, snapshot) {
      final bytes = _gif == null ? null : snapshot.data;
      final loading = snapshot.connectionState == ConnectionState.waiting;
      return Column(
        children: [
          if (bytes != null)
            Image.memory(
              bytes,
              height: 180,
              fit: BoxFit.contain,
              semanticLabel: 'Ilustração de ${catalogName(widget.entry)}',
            ),
          if (snapshot.hasError)
            const Text(
              'GIF indisponível. Confira sua conexão ou siga as instruções.',
            ),
          TextButton(
            onPressed: loading
                ? null
                : () => setState(() {
                    _gif = bytes == null
                        ? _loadOnlineGif(widget.entry, _cancel = CancelToken())
                        : null;
                  }),
            child: Text(
              loading
                  ? 'Carregando GIF…'
                  : bytes == null
                  ? 'Reproduzir GIF online'
                  : 'Fechar GIF',
            ),
          ),
          if (widget.entry['file'] case final String file)
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.https('commons.wikimedia.org', '/wiki/File:$file'),
                  ),
                  child: Text('$file • Wensceslao / Wikimedia Commons'),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.https('creativecommons.org', '/licenses/by-sa/4.0/'),
                  ),
                  child: const Text('CC BY-SA 4.0'),
                ),
              ],
            )
          else
            const Text('Ilustração: Flow • CC0. Primeiro acesso via GitHub.'),
          if (widget.entry['reviewed'] != true)
            const Text(
              'Ilustração não revisada. Pode omitir equipamento ou mostrar outra variante; não use como guia de execução.',
            ),
        ],
      );
    },
  );
}

class _LocalDemonstration extends StatefulWidget {
  final Json entry;
  const _LocalDemonstration(this.entry, {super.key});

  @override
  State<_LocalDemonstration> createState() => _LocalDemonstrationState();
}

class _LocalDemonstrationState extends State<_LocalDemonstration> {
  VideoPlayerController? _player;
  bool _playing = false, _loading = false, _failed = false;
  bool get _video => widget.entry['kind'] == 'mp4';
  String get _asset => '$_media/${widget.entry['id']}';

  Future<void> _toggle() async {
    if (!_video) {
      setState(() => _playing = !_playing);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final player = _player ??= VideoPlayerController.asset('$_asset.mp4');
      if (!player.value.isInitialized) await player.initialize();
      if (!mounted) return;
      if (_playing) {
        await player.pause();
      } else {
        await player.setLooping(true);
        if (!mounted) return;
        await player.play();
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _playing = false;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 180,
        child: _video && _playing && _player!.value.isInitialized
            ? AspectRatio(
                aspectRatio: _player!.value.aspectRatio,
                child: VideoPlayer(_player!),
              )
            : Image.asset(
                _playing ? '$_asset.gif' : '$_asset.${widget.entry['still']}',
                semanticLabel: 'Demonstração de ${catalogName(widget.entry)}',
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Text('Não foi possível abrir a imagem.'),
              ),
      ),
      if (widget.entry['second'] case final String image)
        Image.asset(
          '$_media/$image',
          height: 180,
          fit: BoxFit.contain,
          semanticLabel: 'Segunda posição de ${catalogName(widget.entry)}',
        ),
      if (widget.entry['kind'] != 'image')
        TextButton(
          onPressed: _loading ? null : _toggle,
          child: Text(
            _playing
                ? 'Pausar'
                : _video
                ? 'Reproduzir vídeo offline'
                : 'Reproduzir GIF offline',
          ),
        ),
      if (_failed)
        const Text(
          'Não foi possível reproduzir o vídeo. Use a imagem e as instruções.',
        ),
      if (widget.entry['credit'] case final String credit)
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: () =>
                  launchUrl(Uri.parse(widget.entry['source'] as String)),
              child: Text(credit),
            ),
            TextButton(
              onPressed: () =>
                  launchUrl(Uri.parse(widget.entry['licenseUrl'] as String)),
              child: const Text('Licença'),
            ),
          ],
        )
      else
        Text(_video ? 'Workout Free Videos • CC0' : 'Ilustração: Flow • CC0'),
    ],
  );
}
