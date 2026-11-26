import 'dart:math' as math;

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
  static const units = {
    'Calorias': 'kcal',
    'Proteínas': 'g',
    'Carboidratos': 'g',
    'Gorduras': 'g',
    'Fibras': 'g',
    'Treinos': '',
    'Carga máxima': 'kg',
    'Dias com registro': '',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = MaterialLocalizations.of(context);
    final store = ref.watch(storeProvider);
    ref.watch(changesProvider);
    final now = DateTime.now();
    DateTime date(int index) =>
        DateTime(now.year, now.month, now.day - days + 1 + index);
    String shortDate(DateTime day) => '${day.day}/${day.month}';
    final peak = metric == 'Carga máxima';
    final count = units[metric]!.isEmpty;
    final foodMetric = units[metric] == 'g' || metric == 'Calorias';
    String formatted(double value) =>
        '${count || metric == 'Calorias' ? locale.formatDecimal(value.round()) : value.toStringAsFixed(1).replaceAll('.', ',')}${count ? '' : ' ${units[metric]}'}';
    final grouping = days <= 7
        ? 1
        : days <= 90
        ? 7
        : 30;
    return Scaffold(
      appBar: AppBar(title: const Text('Estatísticas')),
      body: PageBody(
        title: 'Seu histórico',
        subtitle: 'Visão geral',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final d in [7, 30, 90, 365])
                ChoiceChip(
                  label: Text(d == 365 ? '1 ano' : '$d dias'),
                  selected: days == d,
                  onSelected: (_) => setState(() => days = d),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: metric,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Indicador'),
            items: [
              for (final m in units.keys)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => metric = v);
            },
          ),
          const SizedBox(height: 16),
          Load(
            future: Future.wait([store.list('meal'), store.list('session')]),
            builder: (data) {
              final meals = <String, Macros>{};
              for (final record in data[0]) {
                final key = dayKey(
                  DateTime.parse(record.data['date'] as String),
                );
                meals[key] =
                    (meals[key] ?? Macros.zero) +
                    Meal.fromJson(record.data).total;
              }
              final sessions = <String, int>{};
              final loads = <String, double>{};
              for (final record in data[1].where(
                (r) => r.data['finished'] == true,
              )) {
                final key = dayKey(
                  DateTime.parse(record.data['date'] as String),
                );
                sessions.update(key, (n) => n + 1, ifAbsent: () => 1);
                for (final set in (record.data['sets'] as List? ?? [])) {
                  loads[key] = math.max(
                    loads[key] ?? 0,
                    (set['load'] as num).toDouble(),
                  );
                }
              }
              final values = List<double?>.generate(days, (i) {
                final key = dayKey(date(i));
                final food = meals[key];
                return switch (metric) {
                  'Calorias' => food?.kcal,
                  'Proteínas' => food?.protein,
                  'Carboidratos' => food?.carbs,
                  'Gorduras' => food?.fat,
                  'Fibras' => food?.fiber,
                  'Treinos' => sessions[key]?.toDouble(),
                  'Carga máxima' => loads[key],
                  _ =>
                    meals.containsKey(key) || sessions.containsKey(key)
                        ? 1
                        : null,
                };
              });
              final recorded = values.whereType<double>().toList();
              if (recorded.isEmpty) {
                return const EmptyState(
                  'Ainda sem registros neste período',
                  'Escolha outro período ou indicador.',
                  icon: Icons.bar_chart,
                );
              }
              double aggregate(Iterable<double> points) =>
                  points.fold<double>(0, peak ? math.max : (a, b) => a + b);
              // ponytail: blocos fixos de dias, não semanas ou meses do calendário.
              final bars = [
                for (var start = 0; start < days; start += grouping)
                  aggregate(
                    values.skip(start).take(grouping).whereType<double>(),
                  ),
              ];
              final step = math.max(
                1.0,
                (bars.reduce(math.max) / 4).ceilToDouble(),
              );
              final color = foodMetric
                  ? theme.colorScheme.primary
                  : theme.colorScheme.tertiary;
              return Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peak ? 'Maior carga registrada' : 'Total no período',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      formatted(aggregate(recorded)),
                      style: theme.textTheme.headlineMedium,
                    ),
                    Text(
                      '${shortDate(date(0))} a ${shortDate(date(days - 1))} • ${grouping == 1 ? 'Por dia' : 'Blocos de até $grouping dias'}',
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 186,
                      child: BarChart(
                        duration: Duration.zero,
                        BarChartData(
                          minY: 0,
                          maxY: step * 4,
                          borderData: FlBorderData(show: false),
                          gridData: FlGridData(
                            drawVerticalLine: false,
                            horizontalInterval: step,
                            getDrawingHorizontalLine: (_) =>
                                FlLine(color: theme.colorScheme.outlineVariant),
                          ),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(),
                            rightTitles: const AxisTitles(),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 48,
                                interval: step,
                                getTitlesWidget: (value, meta) =>
                                    SideTitleWidget(
                                      meta: meta,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          locale.formatDecimal(value.round()),
                                          style: theme.textTheme.labelSmall,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 24,
                                interval: 1,
                                getTitlesWidget: (value, meta) =>
                                    {
                                      0,
                                      bars.length ~/ 2,
                                      bars.length - 1,
                                    }.contains(value.toInt())
                                    ? SideTitleWidget(
                                        meta: meta,
                                        child: Text(
                                          shortDate(
                                            date(value.toInt() * grouping),
                                          ),
                                          style: theme.textTheme.labelSmall,
                                          maxLines: 1,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              getTooltipColor: (_) =>
                                  theme.colorScheme.inverseSurface,
                              getTooltipItem: (group, index, rod, _) {
                                final start = group.x * grouping;
                                final end =
                                    math.min(days, start + grouping) - 1;
                                final hasData = values
                                    .skip(start)
                                    .take(grouping)
                                    .any((v) => v != null);
                                return BarTooltipItem(
                                  '${shortDate(date(start))}${end == start ? '' : ' a ${shortDate(date(end))}'}\n${hasData ? formatted(rod.toY) : 'Sem registro'}',
                                  TextStyle(
                                    color: theme.colorScheme.onInverseSurface,
                                  ),
                                );
                              },
                            ),
                          ),
                          barGroups: [
                            for (final (i, value) in bars.indexed)
                              BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: value,
                                    color: color,
                                    width: 8,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      peak
                          ? 'Cargas de exercícios diferentes não são diretamente comparáveis.'
                          : 'Sem registro não significa ausência de alimentação ou atividade.',
                      style: theme.textTheme.bodySmall,
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
