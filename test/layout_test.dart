import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:ai_fitness/app/app.dart';
import 'package:ai_fitness/core/store.dart';
import 'package:drift/native.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'core_test.dart' show profile;

void main() {
  testWidgets('dashboard adapta a 320 px; captura tela', (tester) async {
    tester.view.physicalSize = const Size(960, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = LocalStore(NativeDatabase.memory());
    addTearDown(store.close);
    await store.put('profile', {
      ...profile,
      'name': 'Ana',
      'days': 3,
      'minutes': 30,
      'experience': 'Iniciante',
    }, id: 'profile');
    await tester.runAsync(() async {
      final config = jsonDecode(
        await File('.dart_tool/package_config.json').readAsString(),
      ) as Map;
      final flutter = (config['packages'] as List).firstWhere(
        (p) => p['name'] == 'flutter',
      );
      final root = Directory.fromUri(Uri.parse(flutter['rootUri'] as String))
          .parent
          .parent
          .path;
      final font = FontLoader('Roboto')
        ..addFont(
          File('$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)),
        );
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await font.load();
      await icons.load();
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ProviderScope(
          overrides: [storeProvider.overrideWithValue(store)],
          child: const FitnessApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('docs/screenshots').create(recursive: true);
      await File('docs/screenshots/dashboard-test.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  });
}
