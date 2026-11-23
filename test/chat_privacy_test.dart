import 'package:ai_fitness/core/ai.dart';
import 'package:ai_fitness/core/store.dart';
import 'package:ai_fitness/features/ai_assistant/chat.dart';
import 'package:ai_fitness/features/food_analysis/analysis.dart';
import 'package:ai_fitness/features/settings/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const config = AiConfig(
  id: 'test',
  name: 'Teste',
  type: 'OpenAI',
  baseUrl: 'https://api.openai.com/v1',
  model: 'test',
);

void main() {
  for (final brightness in Brightness.values) {
    for (final user in [false, true]) {
      testWidgets('Markdown legível $brightness user=$user', (tester) async {
        final colors = ColorScheme.fromSeed(
          seedColor: const Color(0xffa3ff6f),
          brightness: brightness,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(colorScheme: colors),
            home: Scaffold(
              body: ChatMessageBody(
                user: user,
                data: 'Texto normal **negrito**\n\n# Título\n\n- item\n\n`código`\n\n> citação\n\n[link](https://example.com)',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final style = tester
            .widget<MarkdownBody>(find.byType(MarkdownBody))
            .styleSheet!;
        final expected = user ? colors.onPrimaryContainer : colors.onSurface;
        for (final textStyle in [
          style.p,
          style.h1,
          style.h2,
          style.h3,
          style.h4,
          style.h5,
          style.h6,
          style.code,
          style.blockquote,
          style.listBullet,
          style.tableBody,
          style.a,
        ]) {
          expect(textStyle?.color, expected);
        }
        expect(style.p?.fontWeight, isNot(FontWeight.bold));
        expect(style.strong?.fontWeight, FontWeight.bold);
        final background = user ? colors.primaryContainer : colors.surface;
        final a = expected.computeLuminance(),
            b = background.computeLuminance();
        expect(
          ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final choice in ['remember', 'once', 'cancel', 'dismiss']) {
    testWidgets(
      'consentimento $choice persiste somente autorização explícita',
      (tester) async {
        final store = LocalStore(NativeDatabase.memory());
        addTearDown(store.close);
        bool? result;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [storeProvider.overrideWithValue(store)],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      result = await requestAiConsent(
                        context,
                        config,
                        'Mensagem selecionada.',
                      );
                    },
                    child: const Text('Enviar'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Enviar'));
        await tester.pumpAndSettle();
        expect(find.text('Enviar para Teste?'), findsOneWidget);
        if (choice == 'once') {
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
        }
        if (choice == 'dismiss') {
          await tester.tapAt(const Offset(5, 5));
        } else {
          await tester.tap(
            find.text(choice == 'cancel' ? 'Cancelar' : 'Autorizar envio'),
          );
        }
        await tester.pumpAndSettle();
        expect(result, choice == 'remember' || choice == 'once');
        expect(
          (await store.get('ai-consent'))?['remember'] == true,
          choice == 'remember',
        );
        result = null;
        await tester.tap(find.text('Enviar'));
        await tester.pumpAndSettle();
        expect(
          find.text('Enviar para Teste?'),
          choice == 'remember' ? findsNothing : findsOneWidget,
        );
        if (choice == 'remember') expect(result, true);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'autorização salva vale para outro provedor e pode ser revogada',
    (tester) async {
      final store = LocalStore(NativeDatabase.memory());
      addTearDown(store.close);
      await store.put('settings', {'remember': true}, id: 'ai-consent');
      bool? result;
      final scope = ProviderContainer(
        overrides: [storeProvider.overrideWithValue(store)],
      );
      addTearDown(scope.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await requestAiConsent(
                      context,
                      const AiConfig(
                        id: 'other',
                        name: 'Outro',
                        type: 'OpenAI',
                        baseUrl: 'https://other.example/v1',
                        model: 'other',
                      ),
                      'Foto selecionada.',
                    );
                  },
                  child: const Text('Enviar'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();
      expect(result, true);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Autorização geral de IA'),
        250,
      );
      await tester.ensureVisible(find.text('Revogar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revogar'));
      await tester.pumpAndSettle();
      expect(await store.get('ai-consent'), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
