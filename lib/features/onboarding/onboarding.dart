import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/store.dart';
import '../../shared/ui.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  final bool editing;
  const OnboardingPage({super.key, this.editing = false});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingPage> {
  final controllers = List.generate(12, (_) => TextEditingController());
  int step = 0;
  String goal = goals.first, sex = 'none', experience = 'Iniciante';
  double activity = 1.2;
  bool clinical = false, pregnant = false, gym = false, saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ref.read(storeProvider).get('profile');
    if (p == null || !mounted) return;
    final keys = [
      'name',
      'age',
      'height',
      'weight',
      'targetWeight',
      'days',
      'minutes',
      'equipment',
      'preferences',
      'restrictions',
      'limitations',
      'conditions',
    ];
    for (var i = 0; i < keys.length; i++) {
      controllers[i].text = '${p[keys[i]] ?? ''}';
    }
    setState(() {
      goal = p['goal'] as String;
      sex = p['formulaSex'] as String;
      activity = (p['activity'] as num).toDouble();
      clinical = p['clinical'] == true;
      pregnant = p['pregnant'] == true;
      gym = p['gym'] == true;
      experience = p['experience'] as String;
    });
  }

  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Json profile() => {
    'name': text(controllers[0].text, max: 80),
    'age': number(controllers[1].text, min: 1, max: 120),
    'height': number(controllers[2].text, min: 100, max: 250),
    'weight': number(controllers[3].text, min: 25, max: 350),
    'targetWeight': controllers[4].text.trim().isEmpty
        ? null
        : number(controllers[4].text, min: 25, max: 350),
    'days': controllers[5].text.isEmpty
        ? 3
        : number(controllers[5].text, min: 1, max: 7).round(),
    'minutes': controllers[6].text.isEmpty
        ? 30
        : number(controllers[6].text, min: 10, max: 180).round(),
    'equipment': controllers[7].text,
    'preferences': controllers[8].text,
    'restrictions': controllers[9].text,
    'limitations': controllers[10].text,
    'conditions': controllers[11].text,
    'goal': goal,
    'formulaSex': sex,
    'activity': activity,
    'experience': experience,
    'gym': gym,
    'clinical': clinical,
    'pregnant': pregnant,
  };
  Future<void> next() async {
    try {
      if (step == 0) {
        text(controllers[0].text, max: 80);
        number(controllers[1].text, min: 1, max: 120);
        number(controllers[2].text, min: 100, max: 250);
        number(controllers[3].text, min: 25, max: 350);
      }
      if (step < 4) {
        if (step == 3) {
          profile();
        }
        setState(() => step++);
        return;
      }
      setState(() => saving = true);
      final p = profile();
      final store = ref.read(storeProvider);
      await store.put('profile', p, id: 'profile');
      if ((await store.list('weight')).isEmpty) {
        await store.put('weight', {
          'weight': p['weight'],
          'date': DateTime.now().toIso8601String(),
          'note': 'Registro inicial',
        });
      }
      if (mounted) {
        if (widget.editing) {
          Navigator.pop(context);
        } else {
          context.go('/');
        }
      }
    } catch (e) {
      if (mounted) {
        notice(context, '$e');
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('AI FITNESS'),
      leading: step > 0
          ? IconButton(
              onPressed: () => setState(() => step--),
              icon: const Icon(Icons.arrow_back),
            )
          : null,
    ),
    body: PageBody(
      title: [
        'Seu ponto de partida',
        'Qual sua direção?',
        'Treino que cabe na vida',
        'Comida e cuidado',
        'Tudo no seu ritmo',
      ][step],
      subtitle: 'Seu plano • ${step + 1} de 5',
      children: [
        LinearProgressIndicator(
          value: (step + 1) / 5,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 24),
        if (step == 0) ...[
          const Text(
            'Sem conta, sem assinatura. Seus registros ficam neste aparelho.',
          ),
          const SizedBox(height: 24),
          field(controllers[0], 'Como podemos chamar você?'),
          field(controllers[1], 'Idade (anos)', numeric: true),
          field(controllers[2], 'Altura (cm)', numeric: true),
          field(controllers[3], 'Peso atual (kg)', numeric: true),
          DropdownButtonFormField<String>(
            initialValue: sex,
            decoration: const InputDecoration(
              labelText: 'Coeficiente da fórmula metabólica (opcional)',
            ),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('Não informar')),
              DropdownMenuItem(value: 'female', child: Text('Feminino')),
              DropdownMenuItem(value: 'male', child: Text('Masculino')),
            ],
            onChanged: (v) => setState(() => sex = v!),
          ),
          const SizedBox(height: 12),
          const Text(
            'Usado apenas na estimativa Mifflin-St Jeor. Sem coeficiente, não calculamos meta automática.',
          ),
        ],
        if (step == 1) ...[
          ...goals.map(
            (g) => Panel(
              onTap: () => setState(() => goal = g),
              color: goal == g
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: Row(
                children: [
                  Expanded(child: Text(g)),
                  Icon(goal == g ? Icons.check_circle : Icons.circle_outlined),
                ],
              ),
            ),
          ),
          field(
            controllers[4],
            'Peso desejado em kg (opcional)',
            numeric: true,
          ),
          DropdownButtonFormField<double>(
            initialValue: activity,
            decoration: const InputDecoration(labelText: 'Atividade habitual'),
            items: const [
              DropdownMenuItem(
                value: 1.2,
                child: Text('Baixa • rotina sedentária'),
              ),
              DropdownMenuItem(
                value: 1.375,
                child: Text('Leve • 1–3 dias por semana'),
              ),
              DropdownMenuItem(value: 1.55, child: Text('Moderada • 3–5 dias')),
              DropdownMenuItem(
                value: 1.725,
                child: Text('Alta • rotina ativa'),
              ),
            ],
            onChanged: (v) => setState(() => activity = v!),
          ),
        ],
        if (step == 2) ...[
          DropdownButtonFormField<String>(
            initialValue: experience,
            decoration: const InputDecoration(labelText: 'Experiência'),
            items: [
              'Iniciante',
              'Intermediário',
              'Avançado',
            ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => experience = v!),
          ),
          const SizedBox(height: 16),
          field(
            controllers[5],
            'Dias disponíveis por semana (opcional)',
            numeric: true,
          ),
          field(controllers[6], 'Minutos por treino (opcional)', numeric: true),
          SwitchListTile(
            value: gym,
            onChanged: (v) => setState(() => gym = v),
            title: const Text('Acesso a academia'),
          ),
          field(
            controllers[7],
            'Equipamentos disponíveis (opcional)',
            lines: 2,
          ),
        ],
        if (step == 3) ...[
          field(
            controllers[8],
            'Preferências alimentares (opcional)',
            lines: 2,
          ),
          field(controllers[9], 'Alergias e restrições (opcional)', lines: 2),
          field(controllers[10], 'Lesões ou limitações (opcional)', lines: 2),
          field(controllers[11], 'Condições relevantes (opcional)', lines: 2),
          SwitchListTile(
            value: pregnant,
            onChanged: (v) => setState(() => pregnant = v),
            title: const Text('Gestação'),
          ),
          SwitchListTile(
            value: clinical,
            onChanged: (v) => setState(() => clinical = v),
            title: const Text('Necessidades clínicas específicas'),
            subtitle: const Text('Desativa metas calóricas automáticas.'),
          ),
        ],
        if (step == 4) ...[
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.spa_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  '${controllers[0].text}, seu próximo passo começa aqui.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  '$goal\n$experience • ${controllers[5].text.isEmpty ? 3 : controllers[5].text} dias por semana',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Metas são estimativas, não prescrições. IA pode errar. Revise sugestões e procure orientação profissional quando necessário.',
                ),
              ],
            ),
          ),
          const Text(
            'Fotos nunca são obrigatórias. Nenhum dado será enviado à IA sem autorização. Todas as respostas podem ser editadas depois.',
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: saving ? null : next,
          child: Text(
            saving
                ? 'Salvando…'
                : step == 4
                ? 'Começar minha jornada'
                : 'Continuar',
          ),
        ),
      ],
    ),
  );
}
