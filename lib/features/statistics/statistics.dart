import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/store.dart';
import '../../shared/ui.dart';

class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});
  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsState();
}

class _StatisticsState extends ConsumerState<StatisticsPage> {
  int days = 7;
  String metric = 'Calorias';
  @override
  Widget build(BuildContext context) {
    ref.watch(changesProvider);
    final store = ref.read(storeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Estatísticas')),
      body: PageBody(
        title: 'Olhe o caminho.',
        subtitle: 'Consistência sem pressão',
        children: [
          Wrap(
            spacing: 8,
            children: [7, 30, 90, 365]
                .map(
                  (d) => ChoiceChip(
                    label: Text(d == 365 ? '1 ano' : '$d dias'),
                    selected: days == d,
                    onSelected: (_) => setState(() => days = d),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: metric,
            items: [
              'Calorias',
              'Proteínas',
              'Treinos',
              'Carga máxima',
              'Dias com registro',
            ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (v) => setState(() => metric = v!),
          ),
          const SizedBox(height: 20),
          Load(
            future: Future.wait([store.list('meal'), store.list('session')]),
            builder: (data) {
              final meals = data[0];
              final sessions = data[1];
              final today = DateTime.now();
              final values = List<double>.generate(days, (i) {
                final date = dayKey(
                  DateTime(
                    today.year,
                    today.month,
                    today.day,
                  ).subtract(Duration(days: days - 1 - i)),
                );
                final food = meals.where(
                  (r) =>
                      dayKey(DateTime.parse(r.data['date'] as String)) == date,
                );
                final workouts = sessions.where(
                  (r) =>
                      r.data['finished'] == true &&
                      dayKey(DateTime.parse(r.data['date'] as String)) == date,
                );
                return switch (metric) {
                  'Treinos' => workouts.length.toDouble(),
                  'Carga máxima' =>
                    workouts
                        .expand((r) => r.data['sets'] as List? ?? [])
                        .fold<double>(
                          0,
                          (max, s) => (s['load'] as num).toDouble() > max
                              ? (s['load'] as num).toDouble()
                              : max,
                        ),
                  'Dias com registro' =>
                    food.isNotEmpty || workouts.isNotEmpty ? 1 : 0,
                  _ => food.fold<double>(0, (sum, r) {
                    final m = Meal.fromJson(r.data).total;
                    return sum + (metric == 'Proteínas' ? m.protein : m.kcal);
                  }),
                };
              });
              if (values.every((v) => v == 0)) {
                return const EmptyState(
                  'Ainda sem registros neste período',
                  'Gráficos usam apenas dados que você registrou.',
                );
              }
              return Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metric, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 240,
                      child: LineChart(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 250),
                        LineChartData(
                          minY: 0,
                          borderData: FlBorderData(show: false),
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(
                            topTitles: AxisTitles(),
                            rightTitles: AxisTitles(),
                            bottomTitles: AxisTitles(),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 48,
                              ),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              color: Theme.of(context).colorScheme.primary,
                              spots: values.indexed
                                  .map((e) => FlSpot(e.$1.toDouble(), e.$2))
                                  .toList(),
                              dotData: FlDotData(show: days <= 30),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Total: ${values.fold<double>(0, (a, b) => a + b).toStringAsFixed(1)}${metric == 'Carga máxima' ? ' (soma das máximas diárias em kg)' : ''}',
                    ),
                    const Text(
                      'Dia sem registro não significa ausência de alimentação ou atividade. Cargas de exercícios diferentes não são diretamente comparáveis.',
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
