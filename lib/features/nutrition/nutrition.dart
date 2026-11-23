import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/store.dart';
import '../../core/ai.dart';
import '../../shared/ui.dart';
import '../food_analysis/analysis.dart';
import 'planner.dart';

const mealCategories = [
  'Café da manhã',
  'Almoço',
  'Lanche',
  'Jantar',
  'Ceia',
  'Outra refeição',
];

class NutritionPage extends ConsumerStatefulWidget {
  const NutritionPage({super.key});
  @override
  ConsumerState<NutritionPage> createState() => _NutritionState();
}

class _NutritionState extends ConsumerState<NutritionPage> {
  DateTime day = DateTime.now();
  @override
  Widget build(BuildContext context) {
    ref.watch(changesProvider);
    final store = ref.watch(storeProvider);
    return PageBody(
      title: 'Nutrir é cuidar.',
      subtitle: 'Diário alimentar',
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Dia anterior',
              onPressed: () =>
                  setState(() => day = day.subtract(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: day,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) setState(() => day = date);
                },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(dateLabel(day)),
              ),
            ),
            IconButton(
              tooltip: 'Próximo dia',
              onPressed: () =>
                  setState(() => day = day.add(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Load(
          future: store.daily(day),
          builder: (m) => Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${m.kcal.round()} kcal',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'P ${m.protein.round()} g   •   C ${m.carbs.round()} g   •   G ${m.fat.round()} g\nFibras ${m.fiber.toStringAsFixed(1)} g',
                ),
              ],
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: () => context.push('/meal'),
          icon: const Icon(Icons.add),
          label: const Text('Registrar ou analisar refeição'),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const MealPlannerPage()),
          ),
          icon: const Icon(Icons.event_note_outlined),
          label: const Text('Planejar refeições e lista de compras'),
        ),
        const SizedBox(height: 20),
        Load(
          future: store.list('meal'),
          builder: (records) {
            final meals = records
                .where(
                  (r) =>
                      dayKey(DateTime.parse(r.data['date'] as String)) ==
                      dayKey(day),
                )
                .toList();
            if (meals.isEmpty) {
              return const EmptyState(
                'Seu diário começa aqui',
                'Registre alimentos manualmente, mesmo sem conexão.',
                icon: Icons.restaurant_outlined,
              );
            }
            return Column(
              children: mealCategories.map((category) {
                final list = meals
                    .where((r) => r.data['category'] == category)
                    .toList();
                if (list.isEmpty) return const SizedBox.shrink();
                return Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ...list.map((r) {
                        final meal = Meal.fromJson(r.data);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(meal.name),
                          subtitle: Text(
                            '${meal.total.kcal.round()} kcal • ${meal.ingredients.length} alimentos${meal.ingredients.any((f) => f.estimated) ? ' • contém estimativa da IA' : ''}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/meal?id=${r.id}'),
                        );
                      }),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
        Text('Favoritas', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Load(
          future: store.list('favorite'),
          builder: (favorites) => favorites.isEmpty
              ? const Text(
                  'Salve uma refeição no editor para reutilizar depois.',
                )
              : Column(
                  children: favorites
                      .map(
                        (r) => ListTile(
                          title: Text('${r.data['name']}'),
                          leading: const Icon(Icons.bookmark_outline),
                          onTap: () => context.push('/meal?favorite=${r.id}'),
                          trailing: IconButton(
                            tooltip: 'Excluir favorita',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (await confirm(
                                context,
                                'Excluir favorita?',
                                'O diário não será alterado.',
                                label: 'Excluir',
                              )) {
                                await store.remove(r.id);
                              }
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class MealEditor extends ConsumerStatefulWidget {
  final String? id, favorite;
  const MealEditor({super.key, this.id, this.favorite});
  @override
  ConsumerState<MealEditor> createState() => _MealEditorState();
}

class _MealEditorState extends ConsumerState<MealEditor> {
  final name = TextEditingController();
  List<Ingredient> foods = [];
  DateTime date = DateTime.now();
  String category = mealCategories[1];
  bool saving = false, loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.id != null || widget.favorite != null) {
        final json = await ref
            .read(storeProvider)
            .get(widget.id ?? widget.favorite!);
        if (json != null) {
          final meal = Meal.fromJson(json);
          name.text = meal.name;
          foods = meal.ingredients;
          category = meal.category;
          if (widget.id != null) date = meal.date;
        }
      }
    } catch (e) {
      if (mounted) notice(context, apiError(e));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> editFood({int? index, String? suggested, double? grams}) async {
    final result = await showDialog<Ingredient>(
      context: context,
      builder: (_) => IngredientDialog(
        initial: index == null ? null : foods[index],
        suggested: suggested,
        grams: grams,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          foods.add(result);
        } else {
          foods[index] = result;
        }
      });
    }
  }

  Future<void> save({bool favorite = false}) async {
    try {
      if (foods.isEmpty) {
        throw const FormatException(
          'Adicione pelo menos um alimento com dados nutricionais.',
        );
      }
      if (name.text.trim().length > 120) {
        throw const FormatException(
          'Nome da refeição deve ter até 120 caracteres.',
        );
      }
      final meal = Meal(
        name: name.text.trim().isEmpty ? category : name.text.trim(),
        category: category,
        date: date,
        ingredients: foods,
      );
      setState(() => saving = true);
      await ref
          .read(storeProvider)
          .put(
            favorite ? 'favorite' : 'meal',
            meal.toJson(),
            id: favorite ? null : widget.id,
          );
      if (mounted) {
        HapticFeedback.lightImpact();
        notice(
          context,
          favorite ? 'Refeição salva nas favoritas.' : 'Refeição registrada.',
        );
        if (!favorite) context.pop();
      }
    } catch (e) {
      if (mounted) notice(context, apiError(e));
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final total = foods.fold<Macros>(Macros.zero, (m, f) => m + f.total);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'Sua refeição' : 'Editar refeição'),
        actions: [
          if (widget.id != null)
            IconButton(
              tooltip: 'Excluir registro',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(
                  context,
                  'Excluir refeição?',
                  'Esse registro será removido permanentemente.',
                  label: 'Excluir',
                )) {
                  await ref.read(storeProvider).remove(widget.id!);
                  if (context.mounted) context.pop();
                }
              },
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : PageBody(
              title: 'Do prato ao diário.',
              subtitle: 'Você revisa, você decide',
              children: [
                FoodAnalysis(
                  onFoods: (results) async {
                    final estimates = results.map(Ingredient.fromJson).toList();
                    if (!mounted) return;
                    setState(() => foods.addAll(estimates));
                    notice(
                      context,
                      'Estimativas adicionadas para revisão. Nada registrado ainda.',
                    );
                  },
                ),
                const SizedBox(height: 16),
                field(name, 'Nome da refeição (opcional)'),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Refeição'),
                  items: mealCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => category = v!),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(
                    '${dateLabel(date)} • ${TimeOfDay.fromDateTime(date).format(context)}',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (selected == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(date),
                    );
                    if (time != null) {
                      setState(
                        () => date = DateTime(
                          selected.year,
                          selected.month,
                          selected.day,
                          time.hour,
                          time.minute,
                        ),
                      );
                    }
                  },
                ),
                ...foods.indexed.map(
                  (pair) => Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                pair.$2.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Editar porção',
                              onPressed: () => editFood(index: pair.$1),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Remover ingrediente',
                              onPressed: () =>
                                  setState(() => foods.removeAt(pair.$1)),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        Text(
                          '${pair.$2.grams.toStringAsFixed(0)} g • ${pair.$2.total.kcal.round()} kcal',
                        ),
                        Text(
                          'P ${pair.$2.total.protein.toStringAsFixed(1)} g • C ${pair.$2.total.carbs.toStringAsFixed(1)} g • G ${pair.$2.total.fat.toStringAsFixed(1)} g • Fibras ${pair.$2.total.fiber.toStringAsFixed(1)} g',
                        ),
                        Text(
                          'Fonte: ${pair.$2.source}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (pair.$2.estimated) ...[
                          const Text(
                            'Estimativa da IA • peso e nutrientes aproximados',
                          ),
                          if (pair.$2.uncertainty != null)
                            Text(pair.$2.uncertainty!),
                        ],
                      ],
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => editFood(),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar ingrediente'),
                ),
                const SizedBox(height: 20),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${total.kcal.round()} kcal',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text(
                        'P ${total.protein.toStringAsFixed(1)} g • C ${total.carbs.toStringAsFixed(1)} g • G ${total.fat.toStringAsFixed(1)} g',
                      ),
                      if (foods.any((f) => f.estimated))
                        const Text(
                          'Total inclui estimativas da IA, não valores medidos. Revise porções e preparo antes de registrar.',
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Vou comer: esta tela apenas calcula. Nada entra no diário até você tocar em Já comi. Valores dependem das porções e da fonte informada.',
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: saving ? null : () => save(),
                  child: Text(
                    saving
                        ? 'Salvando…'
                        : widget.id == null
                        ? 'Já comi • registrar'
                        : 'Salvar alterações',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: saving ? null : () => save(favorite: true),
                  icon: const Icon(Icons.bookmark_outline),
                  label: const Text('Salvar refeição favorita'),
                ),
              ],
            ),
    );
  }
}

class IngredientDialog extends StatefulWidget {
  final Ingredient? initial;
  final String? suggested;
  final double? grams;
  const IngredientDialog({super.key, this.initial, this.suggested, this.grams});
  @override
  State<IngredientDialog> createState() => _IngredientState();
}

class _IngredientState extends State<IngredientDialog> {
  late final List<TextEditingController> c;
  String? error;
  late bool estimated;
  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    estimated = f?.estimated ?? false;
    c = [
      f?.name ?? widget.suggested ?? '',
      '${f?.grams ?? widget.grams ?? 100}',
      f == null ? '' : '${f.per100.kcal}',
      f == null ? '' : '${f.per100.protein}',
      f == null ? '' : '${f.per100.carbs}',
      f == null ? '' : '${f.per100.fat}',
      '${f?.per100.fiber ?? 0}',
      f?.source ?? '',
    ].map((value) => TextEditingController(text: value)).toList();
  }

  @override
  void dispose() {
    for (final x in c) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Alimento e porção'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.suggested != null)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'A IA sugeriu identidade e peso. Confirme e use rótulo, TBCA ou TACO para os nutrientes. Nenhum valor nutricional foi inventado.',
                ),
              ),
            field(c[0], 'Nome'),
            field(c[1], 'Quantidade (gramas)', numeric: true),
            if (widget.initial?.estimated == true) ...[
              const Text(
                'Estimativa da IA, não medição nem fonte verificada. Alterar gramas recalcula a porção; nutrientes abaixo continuam por 100 g.',
              ),
              if (widget.initial?.uncertainty != null)
                Text(widget.initial!.uncertainty!),
              CheckboxListTile(
                title: const Text('Mantém valores estimados pela IA'),
                subtitle: const Text(
                  'Desmarque somente ao substituir nutrientes por rótulo ou fonte consultada e atualizar campo Fonte.',
                ),
                value: estimated,
                onChanged: (v) => setState(() => estimated = v == true),
              ),
            ],
            const Text(
              'Valores por 100 g: estimados pela IA ou informados de rótulo/fonte consultada.',
            ),
            const SizedBox(height: 12),
            field(c[2], 'Energia (kcal / 100 g)', numeric: true),
            field(c[3], 'Proteínas (g / 100 g)', numeric: true),
            field(c[4], 'Carboidratos (g / 100 g)', numeric: true),
            field(c[5], 'Gorduras (g / 100 g)', numeric: true),
            field(c[6], 'Fibras (g / 100 g)', numeric: true),
            field(c[7], 'Fonte: rótulo / URL / referência'),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          try {
            final macros = Macros(
              number(c[2].text, max: 950),
              number(c[3].text, max: 100),
              number(c[4].text, max: 100),
              number(c[5].text, max: 100),
              number(c[6].text, max: 100),
            );
            if (macros.protein + macros.carbs + macros.fat > 105) {
              throw const FormatException(
                'Macronutrientes excedem 100 g. Confira a referência.',
              );
            }
            final source = estimated
                ? 'Estimativa da IA — não verificada em tabela ou rótulo'
                : text(c[7].text);
            if (!estimated && source.startsWith('Estimativa da IA')) {
              throw const FormatException(
                'Informe a fonte consultada após substituir os nutrientes estimados.',
              );
            }
            Navigator.pop(
              context,
              Ingredient(
                name: text(c[0].text, max: 120),
                grams: number(c[1].text, min: .1, max: 10000),
                per100: macros,
                source: source,
                estimated: estimated,
                uncertainty: estimated ? widget.initial?.uncertainty : null,
              ),
            );
          } catch (e) {
            setState(() => error = apiError(e));
          }
        },
        child: const Text('Confirmar'),
      ),
    ],
  );
}
