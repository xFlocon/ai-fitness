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
  String decimal(num n, int digits) =>
      n.toStringAsFixed(digits).replaceAll('.', ',');

  String metrics(Json data) {
    final seconds = data['seconds'] as int;
    final meters = data['meters'] as num;
    final time = [
      seconds ~/ 3600,
      seconds ~/ 60 % 60,
      seconds % 60,
    ].map((n) => '$n'.padLeft(2, '0')).join(':');
    final distance = data['fixed'] == true
        ? '${decimal(meters / 1000, 2)} km'
        : 'distância indisponível';
    final average = data['fixed'] == true && seconds > 0
        ? ' • média ${decimal(meters * 3.6 / seconds, 1)} km/h'
        : '';
    final steps = data['mode'] == 'walk'
        ? ' • ${data['steps'] == null ? 'passos indisponíveis' : '${data['steps']} passos'}'
        : '';
    return '$time • $distance$average$steps';
  }

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
          const Text(
            'Permita localização precisa para medir distância e velocidade. Passos na caminhada dependem do sensor e da permissão de atividade física. Rastreamento pode continuar com a tela bloqueada; não feche o app pela lista de recentes. Nenhuma coordenada é salva ou enviada.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: ready && !busy ? () => run('walk') : null,
            icon: const Icon(Icons.directions_walk),
            label: const Text('Iniciar caminhada'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: ready && !busy ? () => run('bike') : null,
            icon: const Icon(Icons.directions_bike),
            label: const Text('Iniciar pedalada'),
          ),
        ] else ...[
          Text(label(state), style: Theme.of(context).textTheme.titleLarge),
          Text(metrics(state)),
          if (state['ended'] == true)
            Text(
              state['error'] as String? ??
                  'Atividade encerrada. Salve o resumo.',
            )
          else if (state['gps'] != true)
            const Text(
              'Buscando sinal GPS. Em área aberta, aguarde antes de começar a se mover.',
            )
          else if (state['speed'] case final num speed)
            Text('Velocidade atual: ${decimal(speed, 1)} km/h'),
          const SizedBox(height: 12),
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
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${label(record.data)} • ${MaterialLocalizations.of(context).formatShortDate(DateTime.parse(record.data['date'] as String))}',
                        ),
                        subtitle: Text(
                          '${metrics(record.data)}\n${calories(record.data)}',
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
