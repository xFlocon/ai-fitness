import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ai.dart';
import '../../core/models.dart';
import '../../core/store.dart';
import '../../shared/ui.dart';
import '../onboarding/onboarding.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(changesProvider);
    final store = ref.read(storeProvider);
    return Load(
      future: store.get('profile').then((p) => p ?? <String, dynamic>{}),
      builder: (p) {
        final targets = p.isEmpty ? null : calculateTargets(p);
        final blocked =
            p.isEmpty ||
            (p['age'] as num) < 18 ||
            p['clinical'] == true ||
            p['pregnant'] == true;
        return PageBody(
          title: '${p['name'] ?? 'Seu perfil'}',
          subtitle: 'Sua jornada é única',
          action: IconButton(
            tooltip: 'Configurações',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    child: const Icon(Icons.person_outline, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${p['goal'] ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${p['height'] ?? '—'} cm • ${p['experience'] ?? ''}\n${p['days'] ?? '—'} dias por semana • ${p['minutes'] ?? '—'} min por treino',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const OnboardingPage(editing: true),
                      ),
                    ),
                    child: const Text('Editar perfil e preferências'),
                  ),
                ],
              ),
            ),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Metas nutricionais',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    targets == null
                        ? 'Sem cálculo automático. Acompanhe hábitos e procure orientação profissional.'
                        : 'Estimativa Mifflin-St Jeor\nGasto diário: ${targets.expenditure.round()} kcal\nMeta inicial: ${targets.macros.kcal.round()} kcal\nP ${targets.macros.protein.round()} g • C ${targets.macros.carbs.round()} g • G ${targets.macros.fat.round()} g\nFibras: ${targets.macros.fiber.round()} g/dia (14 g por 1.000 kcal).',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Margem conservadora: déficit de 10% ou superávit de 5%. Fórmulas podem errar e não substituem avaliação individual.',
                  ),
                  if (!blocked) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const TargetEditor(),
                        ),
                      ),
                      child: const Text('Ajustar metas manualmente'),
                    ),
                  ],
                ],
              ),
            ),
            Panel(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('Inteligência Artificial'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/providers'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: const Text('Evolução e fotos privadas'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/progress'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bar_chart),
                    title: const Text('Estatísticas'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/statistics'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class TargetEditor extends ConsumerStatefulWidget {
  const TargetEditor({super.key});
  @override
  ConsumerState<TargetEditor> createState() => _TargetState();
}

class _TargetState extends ConsumerState<TargetEditor> {
  final c = List.generate(5, (_) => TextEditingController());
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(storeProvider);
    final p = await store.get('profile');
    final j = await store.get('targets');
    if (!mounted || p == null) return;
    final macros = j == null
        ? calculateTargets(p)?.macros
        : Macros.fromTargets(j);
    if (macros != null) {
      final values = [
        macros.kcal,
        macros.protein,
        macros.carbs,
        macros.fat,
        macros.fiber,
      ];
      for (var i = 0; i < c.length; i++) {
        c[i].text = values[i].round().toString();
      }
    }
  }

  @override
  void dispose() {
    for (final x in c) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Metas manuais')),
    body: PageBody(
      title: 'Ajuste com cuidado.',
      subtitle: 'Estimativas editáveis',
      children: [
        ...[
          'Calorias (kcal)',
          'Proteínas (g)',
          'Carboidratos (g)',
          'Gorduras (g)',
          'Fibras por dia (g)',
        ].indexed.map((e) => field(c[e.$1], e.$2, numeric: true)),
        FilledButton(
          onPressed: () async {
            try {
              final p = await ref.read(storeProvider).get('profile');
              if (p == null ||
                  (p['age'] as num) < 18 ||
                  p['clinical'] == true ||
                  p['pregnant'] == true) {
                throw const FormatException(
                  'Metas individualizadas desativadas para este perfil. Procure orientação profissional.',
                );
              }
              final minimum = p['formulaSex'] == 'male' ? 1500.0 : 1200.0;
              final kcal = number(c[0].text, min: minimum, max: 6500);
              final macros = Macros(
                kcal,
                number(c[1].text, max: 400),
                number(c[2].text, max: 1000),
                number(c[3].text, min: 20, max: 300),
                c[4].text.trim().isEmpty
                    ? fiberGoal(kcal)
                    : number(c[4].text, min: 1, max: 100),
              );
              final energy =
                  macros.protein * 4 + macros.carbs * 4 + macros.fat * 9;
              if ((energy - macros.kcal).abs() > macros.kcal * .15) {
                throw const FormatException(
                  'Calorias e macronutrientes diferem mais de 15%. Revise as quantidades.',
                );
              }
              await ref
                  .read(storeProvider)
                  .put('settings', macros.toJson(), id: 'targets');
              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              if (context.mounted) notice(context, apiError(e));
            }
          },
          child: const Text('Salvar metas'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () async {
            await ref.read(storeProvider).remove('targets');
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Restaurar estimativa automática'),
        ),
      ],
    ),
  );
}
