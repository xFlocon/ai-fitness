import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/store.dart';
import '../../shared/ui.dart';
import '../body_progress/progress.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(changesProvider);
    final store = ref.watch(storeProvider);
    return Load(
      future: Future.wait([
        store.get('profile'),
        store.daily(DateTime.now()),
        store.list('workout'),
        store.get('targets'),
      ]),
      builder: (data) {
        final p = data[0] as Json?;
        final consumed = data[1] as Macros;
        final workouts = data[2] as List<Record>;
        final manual = data[3] as Json?;
        final calculated = p == null ? null : calculateTargets(p);
        final blocked =
            p == null ||
            (p['age'] as num) < 18 ||
            p['clinical'] == true ||
            p['pregnant'] == true;
        final target = blocked
            ? null
            : manual == null
            ? calculated?.macros
            : Macros.fromTargets(manual);
        final hour = DateTime.now().hour;
        return PageBody(
          title:
              '${hour < 12
                  ? 'Bom dia'
                  : hour < 18
                  ? 'Boa tarde'
                  : 'Boa noite'}, ${p?['name'] ?? ''}.',
          subtitle: 'Seu progresso, seu ritmo',
          action: IconButton(
            tooltip: 'Configurações',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.tune),
          ),
          children: [
            Panel(
              onTap: () => context.go('/nutrition'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_fire_department_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ENERGIA DO DIA',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      const Icon(Icons.north_east, size: 18),
                    ],
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final ring = SizedBox(
                        width: 156,
                        height: 156,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 0,
                            end: target == null
                                ? 0
                                : (consumed.kcal / target.kcal).clamp(0, 1),
                          ),
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 800),
                          builder: (context, value, _) => Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox.expand(
                                child: CircularProgressIndicator(
                                  value: value,
                                  strokeWidth: 12,
                                  strokeCap: StrokeCap.round,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: .12),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    consumed.kcal.toStringAsFixed(0),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const Text('kcal consumidas'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                      final info = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            target == null
                                ? 'Sem meta automática'
                                : '${(target.kcal - consumed.kcal).clamp(0, 100000).round()} kcal',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            target == null
                                ? 'Acompanhe hábitos sem prescrição.'
                                : 'restantes de ${target.kcal.round()} kcal',
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Cada escolha conta.\nEquilíbrio, não perfeição.',
                          ),
                        ],
                      );
                      return constraints.maxWidth < 330
                          ? Column(
                              children: [
                                ring,
                                const SizedBox(height: 24),
                                info,
                              ],
                            )
                          : Row(
                              children: [
                                ring,
                                const SizedBox(width: 24),
                                Expanded(child: info),
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 28),
                  MacroBar(
                    'Proteínas',
                    consumed.protein,
                    target?.protein,
                    const Color(0xffa3ff6f),
                  ),
                  MacroBar(
                    'Carboidratos',
                    consumed.carbs,
                    target?.carbs,
                    const Color(0xff65b8ff),
                  ),
                  MacroBar(
                    'Gorduras',
                    consumed.fat,
                    target?.fat,
                    const Color(0xffffc67a),
                  ),
                  MacroBar(
                    'Fibras',
                    consumed.fiber,
                    target?.fiber,
                    Theme.of(context).colorScheme.tertiary,
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Refeição'),
                  onPressed: () => context.push('/meal'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.monitor_weight_outlined),
                  label: const Text('Peso'),
                  onPressed: () => context.push('/progress'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.auto_awesome),
                  label: const Text('Conversar'),
                  onPressed: () => context.go('/chat'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Panel(
              onTap: () => context.go('/workouts'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('MOVIMENTO É CUIDADO'),
                  const SizedBox(height: 14),
                  Text(
                    workouts.isEmpty
                        ? 'Seu próximo treino'
                        : '${workouts.first.data['name']}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    workouts.isEmpty
                        ? 'Crie uma rotina com seus equipamentos e disponibilidade.'
                        : '${(workouts.first.data['exercises'] as List).length} exercícios • no seu ritmo',
                  ),
                  const SizedBox(height: 18),
                  FilledButton.tonalIcon(
                    onPressed: () => workouts.isEmpty
                        ? context.go('/workouts')
                        : context.push('/session?id=${workouts.first.id}'),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      workouts.isEmpty ? 'Criar meu treino' : 'Iniciar treino',
                    ),
                  ),
                ],
              ),
            ),
            Panel(
              onTap: () => context.push('/progress'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Sua evolução',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tendências importam mais que oscilações diárias.',
                  ),
                  const SizedBox(height: 16),
                  WeightChart(store: store, days: 30, interactive: false),
                ],
              ),
            ),
            const Text(
              'AI Fitness apoia hábitos. Não substitui nutricionista, médico ou profissional de educação física.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}

class MacroBar extends StatelessWidget {
  final String name;
  final double value;
  final double? target;
  final Color color;
  const MacroBar(this.name, this.value, this.target, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(name)),
            Text(
              '${value.round()}${target == null ? '' : ' / ${target!.round()}'} g',
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: target == null || target! <= 0
              ? 0
              : (value / target!).clamp(0, 1),
          minHeight: 7,
          color: color,
          backgroundColor: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(8),
        ),
      ],
    ),
  );
}
