import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/ai.dart';
import '../../core/models.dart';
import '../../core/store.dart';
import '../../shared/ui.dart';

class WeightChart extends StatelessWidget {
  final LocalStore store;
  final int days;
  const WeightChart({super.key, required this.store, required this.days});
  @override
  Widget build(BuildContext context) => Load(
    future: store.list('weight'),
    builder: (records) {
      final start = DateTime.now().subtract(Duration(days: days));
      final sorted =
          records
              .where(
                (r) => DateTime.parse(r.data['date'] as String).isAfter(start),
              )
              .toList()
            ..sort(
              (a, b) => (a.data['date'] as String).compareTo(
                b.data['date'] as String,
              ),
            );
      if (sorted.isEmpty) {
        return const SizedBox(
          height: 120,
          child: Center(
            child: Text('Registre seu peso para acompanhar tendências.'),
          ),
        );
      }
      return SizedBox(
        height: 180,
        child: LineChart(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
          LineChartData(
            minX: 0,
            maxX: days.toDouble(),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 40),
              ),
              topTitles: AxisTitles(),
              rightTitles: AxisTitles(),
              bottomTitles: AxisTitles(),
            ),
            lineBarsData: [
              LineChartBarData(
                isCurved: false,
                color: Theme.of(context).colorScheme.primary,
                barWidth: 3,
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).colorScheme.primary
                          .withValues(alpha: .18),
                      Colors.transparent,
                    ],
                  ),
                ),
                spots: sorted
                    .map(
                      (r) => FlSpot(
                        DateTime.parse(r.data['date'] as String)
                                .difference(start)
                                .inMinutes /
                            1440,
                        (r.data['weight'] as num).toDouble(),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class ProgressPage extends ConsumerStatefulWidget {
  const ProgressPage({super.key});
  @override
  ConsumerState<ProgressPage> createState() => _ProgressState();
}

class _ProgressState extends ConsumerState<ProgressPage> {
  int days = 30;
  final selected = <String>{};
  Future<void> addPhoto() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (photo == null) return;
      if (await photo.length() > 8 * 1024 * 1024) {
        throw const FormatException('Fotografia maior que 8 MB.');
      }
      final store = ref.read(storeProvider);
      final id = store.newId();
      final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/photos',
      );
      await dir.create(recursive: true);
      final file = await File(photo.path).copy('${dir.path}/$id.jpg');
      try {
        await store.put('photo', {
          'photo': file.path,
          'date': DateTime.now().toIso8601String(),
        }, id: id);
      } catch (_) {
        await file.delete();
        rethrow;
      }
    } catch (e) {
      if (mounted) notice(context, apiError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(changesProvider);
    final store = ref.read(storeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Evolução corporal')),
      body: PageBody(
        title: 'Além da balança.',
        subtitle: 'Tendências, não julgamentos',
        children: [
          Wrap(
            spacing: 8,
            children: [7, 30, 90, 365]
                .map(
                  (d) => ChoiceChip(
                    label: Text(d == 365 ? '1 ano' : '$d dias'),
                    selected: d == days,
                    onSelected: (_) => setState(() => days = d),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
          Panel(
            child: WeightChart(store: store, days: days),
          ),
          FilledButton.icon(
            onPressed: () async {
              final input = await ask(
                context,
                'Registrar peso em kg',
                numeric: true,
              );
              if (input == null) return;
              try {
                final value = number(input, min: 25, max: 350);
                if (!context.mounted) return;
                final note = await ask(context, 'Observação (opcional)');
                await store.put('weight', {
                  'weight': value,
                  'date': DateTime.now().toIso8601String(),
                  'note': note ?? '',
                });
              } catch (e) {
                if (context.mounted) notice(context, apiError(e));
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Registrar peso'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              final input = await ask(
                context,
                'Medidas e observações',
                lines: 5,
              );
              if (input == null || input.trim().isEmpty) return;
              try {
                await store.put('measurement', {
                  'note': text(input, max: 4000),
                  'date': DateTime.now().toIso8601String(),
                });
              } catch (e) {
                if (context.mounted) notice(context, apiError(e));
              }
            },
            child: const Text('Adicionar medidas ou observações'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Peso varia com hidratação, digestão e outros fatores. Fotos não medem gordura corporal.',
          ),
          const SizedBox(height: 20),
          Load(
            future: store.list('weight'),
            builder: (records) => Column(
              children: records
                  .map(
                    (r) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.monitor_weight_outlined),
                      title: Text('${r.data['weight']} kg'),
                      subtitle: Text(
                        '${dateLabel(DateTime.parse(r.data['date'] as String))} • ${r.data['note'] ?? ''}',
                      ),
                      onTap: () async {
                        final input = await ask(
                          context,
                          'Editar peso em kg',
                          initial: '${r.data['weight']}',
                          numeric: true,
                        );
                        if (input == null) return;
                        try {
                          await store.put('weight', {
                            ...r.data,
                            'weight': number(input, min: 25, max: 350),
                          }, id: r.id);
                        } catch (e) {
                          if (context.mounted) notice(context, apiError(e));
                        }
                      },
                      trailing: IconButton(
                        tooltip: 'Excluir peso',
                        onPressed: () async {
                          if (await confirm(
                            context,
                            'Excluir peso?',
                            'O registro será removido permanentemente.',
                            label: 'Excluir',
                          )) {
                            await store.remove(r.id);
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Load(
            future: store.list('measurement'),
            builder: (records) => Column(
              children: records
                  .map(
                    (r) => ListTile(
                      title: Text('${r.data['note']}'),
                      subtitle: Text(
                        dateLabel(DateTime.parse(r.data['date'] as String)),
                      ),
                      trailing: IconButton(
                        tooltip: 'Excluir observação',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirm(
                            context,
                            'Excluir observação?',
                            'Registro será removido.',
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
          const SizedBox(height: 24),
          Text('Fotos privadas', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Opcionais e locais. Selecione duas fotos para comparar. Nenhuma foto corporal é enviada à IA.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: addPhoto,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Adicionar foto'),
          ),
          const SizedBox(height: 12),
          Load(
            future: store.list('photo'),
            builder: (photos) => Column(
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: photos
                      .map(
                        (r) => SizedBox(
                          width: 140,
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () => setState(() {
                                  if (!selected.remove(r.id) &&
                                      selected.length < 2) {
                                    selected.add(r.id);
                                  }
                                }),
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.file(
                                        File(r.data['photo'] as String),
                                        height: 170,
                                        width: 140,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            const SizedBox(
                                              height: 170,
                                              child: Center(
                                                child: Text(
                                                  'Foto indisponível',
                                                ),
                                              ),
                                            ),
                                      ),
                                    ),
                                    if (selected.contains(r.id))
                                      const Positioned(
                                        right: 8,
                                        top: 8,
                                        child: Icon(
                                          Icons.check_circle,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      dateLabel(
                                        DateTime.parse(
                                          r.data['date'] as String,
                                        ),
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Excluir foto permanentemente',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      if (!await confirm(
                                        context,
                                        'Excluir foto?',
                                        'A cópia privada do aplicativo será apagada. O original da galeria não será alterado.',
                                        label: 'Excluir',
                                      )) {
                                        return;
                                      }
                                      try {
                                        final file = File(
                                          r.data['photo'] as String,
                                        );
                                        if (await file.exists()) {
                                          await file.delete();
                                        }
                                        await store.remove(r.id);
                                        selected.remove(r.id);
                                      } catch (e) {
                                        if (context.mounted) {
                                          notice(context, apiError(e));
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
                if (selected.length == 2)
                  FilledButton(
                    onPressed: () {
                      final pair = photos
                          .where((r) => selected.contains(r.id))
                          .toList();
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              PhotoComparison(left: pair[0], right: pair[1]),
                        ),
                      );
                    },
                    child: const Text('Comparar selecionadas'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PhotoComparison extends StatefulWidget {
  final Record left, right;
  const PhotoComparison({super.key, required this.left, required this.right});
  @override
  State<PhotoComparison> createState() => _PhotoComparisonState();
}

class _PhotoComparisonState extends State<PhotoComparison> {
  double value = .5;
  bool sideBySide = false;
  Widget photo(Record r) => Image.file(
    File(r.data['photo'] as String),
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const Center(child: Text('Foto indisponível')),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Comparação privada'),
      actions: [
        IconButton(
          tooltip: 'Alternar lado a lado',
          onPressed: () => setState(() => sideBySide = !sideBySide),
          icon: const Icon(Icons.compare),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '${dateLabel(DateTime.parse(widget.left.data['date'] as String))}  •  ${dateLabel(DateTime.parse(widget.right.data['date'] as String))}\nUse pinça para ampliar. Imagens não são medições clínicas.',
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: LayoutBuilder(
              builder: (context, c) => SizedBox(
                width: c.maxWidth,
                height: c.maxHeight,
                child: sideBySide
                    ? Row(
                        children: [
                          Expanded(child: photo(widget.left)),
                          Expanded(child: photo(widget.right)),
                        ],
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          photo(widget.right),
                          ClipRect(
                            clipper: _CompareClip(value),
                            child: photo(widget.left),
                          ),
                          Positioned(
                            left: c.maxWidth * value,
                            top: 0,
                            bottom: 0,
                            child: Container(width: 2, color: Colors.white),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        if (!sideBySide)
          Slider(
            value: value,
            semanticFormatterCallback: (v) => '${(v * 100).round()} por cento',
            onChanged: (v) => setState(() => value = v),
          ),
      ],
    ),
  );
}

class _CompareClip extends CustomClipper<Rect> {
  final double fraction;
  _CompareClip(this.fraction);
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);
  @override
  bool shouldReclip(_CompareClip oldClipper) => oldClipper.fraction != fraction;
}
