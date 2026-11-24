import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/ai.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';

const videoKeySlot = 'youtube-data-api';
final _exerciseTerm = RegExp(r'^[\p{L}\p{M}0-9 ()-]{1,120}$', unicode: true);

String exerciseVideoQuery(Object? suggested, String name) {
  final term = suggested is String ? suggested.trim() : '';
  if (_exerciseTerm.hasMatch(term)) return term;
  return name
      .replaceAll(RegExp(r'[^\p{L}\p{M}0-9 ()-]+', unicode: true), ' ')
      .trim();
}

// Search uses only exercise terms. AI-supplied links and domains never enter the player.
Future<List<String?>> findExerciseVideos(
  List<String> queries,
  String key, {
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
    final response = await dio.get<Json>(
      'https://www.googleapis.com/youtube/v3/$endpoint',
      queryParameters: parameters,
      options: Options(headers: {'X-Goog-Api-Key': key}),
      cancelToken: cancel,
    );
    return (response.data?['items'] as List? ?? []).whereType<Json>().toList();
  }

  try {
    // ponytail: two candidates per term; use YouTube ranking, not frame-level form analysis.
    final candidates = await Future.wait(
      queries.toSet().map((query) async {
        final hits = await get('search', {
          'part': 'id',
          'type': 'video',
          'q': '$query exercise proper form tutorial',
          'videoDuration': 'short',
          'videoEmbeddable': 'true',
          'safeSearch': 'strict',
          'maxResults': 2,
        });
        return MapEntry(
          query,
          hits
              .map((hit) => youtubeVideoId((hit['id'] as Map?)?['videoId']))
              .nonNulls
              .toList(),
        );
      }),
    );
    final byQuery = Map.fromEntries(candidates);
    final ids = byQuery.values.expand((ids) => ids).toSet();
    if (ids.isEmpty) return List.filled(queries.length, null);
    final videos = await get('videos', {
      'part': 'status,contentDetails',
      'id': ids.join(','),
    });
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
          return status?['embeddable'] == true &&
              status?['privacyStatus'] == 'public' &&
              seconds > 0 &&
              seconds < 240;
        })
        .map((video) => video['id'])
        .toSet();
    return queries
        .map((q) => byQuery[q]!.where(usable.contains).firstOrNull)
        .toList();
  } finally {
    if (client == null) dio.close(force: true);
  }
}

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
