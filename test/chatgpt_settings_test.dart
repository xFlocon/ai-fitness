import 'package:ai_fitness/core/store.dart';
import 'package:ai_fitness/features/settings/chatgpt_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
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
