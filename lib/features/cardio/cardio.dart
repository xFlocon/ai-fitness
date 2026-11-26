import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../core/store.dart';
import '../../shared/ui.dart';

double? cardioCalories({
  required bool bike,
  required double kg,
  required double meters,
  required int seconds,
}) {
  if (!kg.isFinite ||
      kg <= 0 ||
      !meters.isFinite ||
      meters < 25 ||
      seconds < 30) {
    return null;
  }
  final speed = meters * 3.6 / seconds;
  final met = bike
      ? (speed < 16
            ? 4.0
            : speed < 22
            ? 6.8
            : 8.0)
      : (speed < 3.2
            ? 2.0
            : speed < 4.8
            ? 3.0
            : speed < 5.6
            ? 3.8
            : 4.8);
  // ponytail: coarse net MET estimate; no grade, heart rate, or power model.
  return (met - 1) * 3.5 * kg / 200 * seconds / 60;
}

class CardioPage extends ConsumerStatefulWidget {
  const CardioPage({super.key});

  @override
  ConsumerState<CardioPage> createState() => _CardioPageState();
}

class _CardioPageState extends ConsumerState<CardioPage> {
  static const channel = MethodChannel('ai_fitness/cardio');
  late final Timer timer;
  Json? activity, summary;
  String? error;
  bool ready = false, busy = false, reading = false;

  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!ready || activity?['ended'] == false) refresh();
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (busy || reading) return;
    reading = true;
    try {
      final state = await channel.invokeMapMethod<String, dynamic>('status');
      if (mounted && !busy) {
        setState(() {
          activity = state;
          ready = true;
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          ready = true;
          error = 'Rastreamento disponível no app Android.';
        });
      }
    } on PlatformException {
      if (mounted) {
        setState(() {
          error = 'Não foi possível consultar o rastreamento.';
        });
      }
    } finally {
      reading = false;
    }
  }

  Future<void> run([String? mode]) async {
    final store = ref.read(storeProvider);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final state = await channel.invokeMapMethod<String, dynamic>(
        mode == null ? 'finish' : 'start',
        mode,
      );
      if (mounted) {
        setState(() {
          activity = state;
          if (mode != null) summary = null;
        });
      }
      if (mode != null || state == null) return;
      final profile = await store.get('profile');
      final meters = (state['meters'] as num).toDouble();
      final seconds = state['seconds'] as int;
      final record = <String, dynamic>{
        'mode': state['mode'],
        'date': DateTime.now().toIso8601String(),
        'seconds': seconds,
        'meters': meters,
        'fixed': state['fixed'],
        'steps': state['steps'],
        'kcal': cardioCalories(
          bike: state['mode'] == 'bike',
          kg: (profile?['weight'] as num?)?.toDouble() ?? 0,
          meters: meters,
          seconds: seconds,
        ),
      };
      await store.put('cardio', record, id: 'cardio-${state['id']}');
      await channel.invokeMethod<void>('clear', state['id']);
      if (mounted) {
        setState(() {
          activity = null;
          summary = record;
          error = state['error'] as String?;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => error = e.message ?? 'Falha no rastreamento. Tente novamente.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível concluir. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String label(Json data) => data['mode'] == 'bike' ? 'Pedalada' : 'Caminhada';
  IconData modeIcon(Json data) =>
      data['mode'] == 'bike' ? Icons.directions_bike : Icons.directions_walk;

  String decimal(num n, int digits) =>
      n.toStringAsFixed(digits).replaceAll('.', ',');

  String elapsed(int seconds) => [
    seconds ~/ 3600,
    seconds ~/ 60 % 60,
    seconds % 60,
  ].map((n) => '$n'.padLeft(2, '0')).join(':');

  String metrics(Json data) {
    final seconds = data['seconds'] as int;
    final meters = data['meters'] as num;
    final distance = data['fixed'] == true
        ? '${decimal(meters / 1000, 2)} km'
        : 'distância indisponível';
    final average = data['fixed'] == true && seconds > 0
        ? ' • média ${decimal(meters * 3.6 / seconds, 1)} km/h'
        : '';
    final steps = data['mode'] == 'walk'
        ? ' • ${data['steps'] == null ? 'passos indisponíveis' : '${data['steps']} passos'}'
        : '';
    return '${elapsed(seconds)} • $distance$average$steps';
  }

  Widget liveMetrics(BuildContext context, Json state) {
    final theme = Theme.of(context).textTheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(modeIcon(state)),
              Text(label(state), style: theme.titleLarge),
            ],
          ),
          const SizedBox(height: 12),
          Text(elapsed(state['seconds'] as int), style: theme.displaySmall),
          const Text('Tempo de atividade'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _metric(
                theme,
                'Distância',
                state['fixed'] == true
                    ? '${decimal((state['meters'] as num) / 1000, 2)} km'
                    : '—',
              ),
              _metric(
                theme,
                'Velocidade',
                state['gps'] == true && state['speed'] is num
                    ? '${decimal(state['speed'] as num, 1)} km/h'
                    : '—',
              ),
              if (state['mode'] == 'walk')
                _metric(
                  theme,
                  'Passos',
                  state['steps'] == null ? '—' : '${state['steps']} passos',
                ),
            ],
          ),
          if (state['ended'] == true || state['gps'] != true) ...[
            const SizedBox(height: 12),
            Text(
              state['ended'] == true
                  ? state['error'] as String? ??
                        'Atividade encerrada. Salve o resumo.'
                  : 'Buscando sinal GPS. Aguarde em área aberta.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(TextTheme theme, String name, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: theme.titleMedium),
      Text(name),
    ],
  );

  String calories(Json data) {
    final kcal = data['kcal'] as num?;
    return kcal == null
        ? 'Sem estimativa de calorias: precisa de peso, duração e distância suficientes.'
        : '≈ ${kcal.round()} kcal ativas (estimativa)';
  }

  @override
  Widget build(BuildContext context) {
    final state = activity;
    final result = summary;
    return PageBody(
      title: 'Caminhada e pedalada',
      subtitle: 'Cardio',
      children: [
        if (error != null) Text(error!),
        if (state == null) ...[
          FilledButton.icon(
            onPressed: ready && !busy ? () => run('walk') : null,
            icon: const Icon(Icons.directions_walk),
            label: const Text('Iniciar caminhada'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: ready && !busy ? () => run('bike') : null,
            icon: const Icon(Icons.directions_bike),
            label: const Text('Iniciar pedalada'),
          ),
          const SizedBox(height: 8),
          const ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline),
            title: Text('GPS, passos e privacidade'),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use localização precisa para medir distância e velocidade. Passos dependem do sensor e da permissão de atividade física. O rastreamento pode continuar com a tela bloqueada; não feche o app pela lista de recentes. Nenhuma coordenada é salva ou enviada.',
              ),
            ],
          ),
        ] else ...[
          liveMetrics(context, state),
          FilledButton(
            onPressed: busy ? null : () => run(),
            child: Text(
              state['ended'] == true
                  ? 'Salvar resumo'
                  : state['mode'] == 'bike'
                  ? 'Terminar pedalada'
                  : 'Terminar caminhada',
            ),
          ),
        ],
        if (result != null) ...[
          const SizedBox(height: 16),
          Text(
            '${label(result)} concluída',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(metrics(result)),
          Text(calories(result)),
          const Text(
            'Estimativa acima do repouso, com peso do perfil, tempo total e velocidade média. Não é medição.',
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'Histórico de cardio',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Load(
          future: ref.watch(cardioHistoryProvider.future),
          builder: (records) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: records.isEmpty
                ? [const Text('Nenhuma atividade registrada.')]
                : [
                    for (final record in records)
                      Card(
                        child: ListTile(
                          leading: Icon(modeIcon(record.data)),
                          title: Text(label(record.data)),
                          subtitle: Text(
                            '${MaterialLocalizations.of(context).formatShortDate(DateTime.parse(record.data['date'] as String))}\n${metrics(record.data)}\n${calories(record.data)}',
                          ),
                        ),
                      ),
                  ],
          ),
        ),
      ],
    );
  }
}

final cardioHistoryProvider = FutureProvider((ref) {
  ref.watch(changesProvider);
  return ref.watch(storeProvider).list('cardio');
});
