import 'package:ai_fitness/core/store.dart';
import 'package:ai_fitness/features/settings/chatgpt_settings.dart';
import 'package:ai_fitness/features/settings/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('descobre modelos sem nome ou ID e mantém consentimento', (
    tester,
  ) async {
    final store = LocalStore(NativeDatabase.memory());
    addTearDown(store.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: const MaterialApp(home: ProviderEditor()),
      ),
    );
    final discover = find.text('Descobrir modelos');
    await tester.ensureVisible(discover);
    await tester.tap(discover);
    await tester.runAsync(() async {
      await store.get('ai-consent');
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Será feita uma consulta de modelos'),
      findsOneWidget,
    );
    expect(find.text('Texto ausente ou muito longo.'), findsNothing);
  });
  testWidgets('login ChatGPT tem botão oficial e não pede chave ou senha', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = LocalStore(NativeDatabase.memory());
    addTearDown(store.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: const MaterialApp(home: ChatGptSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continuar com ChatGPT'), findsOneWidget);
    expect(find.textContaining('auth.openai.com'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
