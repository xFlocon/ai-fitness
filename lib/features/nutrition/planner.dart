import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai.dart';
import '../../core/chatgpt.dart';
import '../../core/models.dart';
import '../../core/store.dart';
import '../../shared/ui.dart';
import '../food_analysis/analysis.dart';

Json validateMealPlan(String response) {
  final json = parseObject(response);
  final recipes = json['recipes'];
  final shopping = json['shopping'];
  if (recipes is! List ||
      recipes.isEmpty ||
      recipes.length > 10 ||
      shopping is! List ||
      shopping.length > 100) {
    throw const FormatException('Plano alimentar inválido.');
  }
  return {
    'recipes': recipes.map((r) {
      if (r is! Json ||
          r['ingredients'] is! List ||
          (r['ingredients'] as List).length > 30) {
        throw const FormatException('Receita inválida.');
      }
      return {
        'name': text(r['name'], max: 150),
        'ingredients': (r['ingredients'] as List)
            .map((i) => text(i, max: 200))
            .toList(),
        'instructions': text(r['instructions'], max: 3000),
      };
    }).toList(),
    'shopping': shopping.map((i) => text(i, max: 200)).toList(),
  };
}

class MealPlannerPage extends ConsumerStatefulWidget {
  const MealPlannerPage({super.key});
  @override
  ConsumerState<MealPlannerPage> createState() => _PlannerState();
}

class _PlannerState extends ConsumerState<MealPlannerPage> {
  final c = List.generate(5, (_) => TextEditingController());
  bool busy = false;
  CancelToken? cancel;
  @override
  void initState() {
    super.initState();
    c[4].text = '3';
  }

  @override
  void dispose() {
    cancel?.cancel();
    for (final x in c) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> generate() async {
    try {
      final request = {
        'available': text(c[0].text, max: 4000),
        'preferences': c[1].text,
        'restrictions': c[2].text,
        'budget': c[3].text,
        'meals': number(c[4].text, min: 1, max: 10).round(),
      };
      final store = ref.read(storeProvider);
      final cfg = await taskConfig(store, 'planning');
      if (!mounted) return;
      if (!await requestAiConsent(
        context,
        cfg,
        'Serão enviados somente alimentos disponíveis, preferências, restrições, orçamento e número de refeições digitados nesta tela:\n${jsonEncode(request)}',
      )) {
        return;
      }
      if (!mounted) return;
      setState(() => busy = true);
      cancel = CancelToken();
      final provider = await configuredProvider(cfg);
      var answer = '';
      await for (final part in provider.generate(
        [
          {
            'role': 'user',
            'content':
                'Sugira combinações culinárias, não prescrição nutricional. Respeite alergias, restrições e orçamento: ${jsonEncode(request)}. Não invente calorias, nutrientes, preços ou referências. Retorne SOMENTE JSON: {"recipes":[{"name":"nome","ingredients":["ingrediente e quantidade culinária"],"instructions":"preparo e cuidados de segurança alimentar"}],"shopping":["item a comprar"]}. Máximo 10 receitas e 100 itens.',
          },
        ],
        system: assistantSystem,
        cancel: cancel,
      )) {
        answer += part;
      }
      final plan = validateMealPlan(answer);
      if (!mounted) return;
      if (!await confirm(
        context,
        'Salvar sugestões para revisão?',
        '${(plan['recipes'] as List).map((r) => r['name']).join('\n')}\n\nRevise ingredientes e alergênicos. Não há cálculo nutricional ou garantia de preços. Nada será registrado no diário.',
        label: 'Salvar sugestões',
      )) {
        return;
      }
      await store.put('plan', {
        ...plan,
        'date': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (mounted) notice(context, apiError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(changesProvider);
    final store = ref.read(storeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Planejar refeições')),
      body: PageBody(
        title: 'Mais ideias para sua mesa.',
        subtitle: 'Ingredientes reais, escolhas suas',
        children: [
          ...[
            'Alimentos disponíveis',
            'Preferências (opcional)',
            'Alergias e restrições (opcional)',
            'Orçamento e moeda (opcional)',
            'Número de refeições (1–10)',
          ].indexed.map(
            (e) => field(
              c[e.$1],
              e.$2,
              numeric: e.$1 == 4,
              lines: e.$1 < 3 ? 2 : 1,
            ),
          ),
          FilledButton.icon(
            onPressed: busy ? null : generate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Sugerir combinações com IA'),
          ),
          if (busy) ...[
            const LinearProgressIndicator(),
            TextButton(
              onPressed: () => cancel?.cancel(),
              child: const Text('Cancelar'),
            ),
          ],
          const SizedBox(height: 24),
          Load(
            future: store.list('plan'),
            builder: (plans) => Column(
              children: plans
                  .map(
                    (r) => Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Plano de ${dateLabel(DateTime.parse(r.data['date'] as String))}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          ...(r.data['recipes'] as List).map(
                            (recipe) => ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text('${recipe['name']}'),
                              children: [
                                Text(
                                  '${(recipe['ingredients'] as List).join('\n')}\n\n${recipe['instructions']}',
                                ),
                                TextButton(
                                  onPressed: () async {
                                    try {
                                      final list = (await store.list(
                                        'shopping',
                                      )).map((i) => i.data['label']).toSet();
                                      for (final item
                                          in recipe['ingredients'] as List) {
                                        if (list.add(item)) {
                                          await store.put('shopping', {
                                            'label': item,
                                            'checked': false,
                                          });
                                        }
                                      }
                                      if (context.mounted) {
                                        notice(
                                          context,
                                          'Ingredientes adicionados à lista.',
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        notice(context, apiError(e));
                                      }
                                    }
                                  },
                                  child: const Text(
                                    'Adicionar ingredientes à lista',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              if (await confirm(
                                context,
                                'Excluir plano?',
                                'Sugestões serão removidas. Lista de compras será mantida.',
                                label: 'Excluir',
                              )) {
                                await store.remove(r.id);
                              }
                            },
                            child: const Text('Excluir plano'),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Text(
            'Lista de compras',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final item = await ask(context, 'Item da lista');
              if (item == null) return;
              try {
                await store.put('shopping', {
                  'label': text(item, max: 200),
                  'checked': false,
                });
              } catch (e) {
                if (context.mounted) notice(context, apiError(e));
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Adicionar item'),
          ),
          Load(
            future: store.list('shopping'),
            builder: (items) => items.isEmpty
                ? const Text(
                    'Sua lista está vazia. Itens salvos funcionam offline.',
                  )
                : Column(
                    children: items
                        .map(
                          (r) => Row(
                            children: [
                              Expanded(
                                child: CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: r.data['checked'] == true,
                                  title: Text('${r.data['label']}'),
                                  onChanged: (v) => store.put('shopping', {
                                    ...r.data,
                                    'checked': v,
                                  }, id: r.id),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Editar item',
                                onPressed: () async {
                                  final label = await ask(
                                    context,
                                    'Editar item',
                                    initial: '${r.data['label']}',
                                  );
                                  if (label == null) return;
                                  try {
                                    await store.put('shopping', {
                                      ...r.data,
                                      'label': text(label, max: 200),
                                    }, id: r.id);
                                  } catch (e) {
                                    if (context.mounted) {
                                      notice(context, apiError(e));
                                    }
                                  }
                                },
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Remover item',
                                onPressed: () async {
                                  try {
                                    await store.remove(r.id);
                                  } catch (e) {
                                    if (context.mounted) {
                                      notice(context, apiError(e));
                                    }
                                  }
                                },
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
