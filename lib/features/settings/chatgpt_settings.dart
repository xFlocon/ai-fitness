import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ai.dart';
import '../../core/chatgpt.dart';
import '../../core/models.dart';
import '../../core/store.dart';
import '../../shared/ui.dart';
import '../food_analysis/analysis.dart';

class ChatGptSettingsPage extends ConsumerStatefulWidget {
  final String? id;
  const ChatGptSettingsPage({super.key, this.id});
  @override
  ConsumerState<ChatGptSettingsPage> createState() => _ChatGptSettingsState();
}

class _ChatGptSettingsState extends ConsumerState<ChatGptSettingsPage> {
  final auth = ChatGptAuth.instance;
  final name = TextEditingController(text: 'Meu ChatGPT');
  List<Json> accounts = [];
  List<String> models = [];
  String? accountId, model, status;
  bool busy = true, images = false;
  CancelToken? cancel;
  late final String id;

  @override
  void initState() {
    super.initState();
    id = widget.id ?? ref.read(storeProvider).newId();
    load();
  }

  Future<void> load() async {
    try {
      final saved = widget.id == null
          ? null
          : await ref.read(storeProvider).get(id);
      final list = await auth.accounts();
      if (!mounted) return;
      setState(() {
        accounts = list;
        if (saved != null) {
          name.text = saved['name'] as String;
          accountId = saved['authId'] as String?;
          model = saved['model'] as String;
          images = saved['images'] == true;
          models = [model!];
        }
      });
    } catch (e) {
      if (mounted) setState(() => status = apiError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  AiConfig config() => AiConfig(
    id: id,
    name: text(name.text, max: 100),
    type: chatGptType,
    baseUrl: 'https://api.openai.com/v1',
    model: text(model, max: 200),
    authId: text(accountId),
    images: images,
  );

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      status = null;
    });
    cancel = CancelToken();
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => status = apiError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> login({bool add = false}) => run(() async {
    final selected = await auth.signIn(
      accountId: add ? null : accountId,
      cancel: cancel!,
    );
    final list = await auth.accounts();
    if (!mounted) return;
    setState(() {
      accounts = list;
      accountId = selected;
      models = [];
      model = null;
      final enabled =
          list.firstWhere((a) => a['id'] == selected)['enabled'] == true;
      status = enabled
          ? 'Conta validada. Descubra modelos e teste conexão antes de salvar.'
          : 'Conta conectada sem permissão de uso do plano. Entre novamente para autorizar ou use outro provedor.';
    });
  });

  Future<void> discover() => run(() async {
    final cfg = AiConfig(
      id: id,
      name: 'ChatGPT',
      type: chatGptType,
      baseUrl: 'https://api.openai.com/v1',
      model: model ?? 'catalog',
      authId: accountId,
    );
    if (!await requestAiConsent(
      context,
      cfg,
      'Será consultado catálogo da conta ChatGPT conectada. Nenhum dado de saúde será enviado.',
    )) {
      return;
    }
    if (cancel!.isCancelled) throw const AiFailure('Operação cancelada.');
    final list = await ChatGptProvider(cfg).models(cancel: cancel);
    if (!mounted) return;
    setState(() {
      models = list;
      if (!list.contains(model)) model = list.firstOrNull;
      status =
          '${list.length} modelos encontrados. Catálogo não garante autorização; teste geração.';
    });
  });

  Future<void> test() => run(() async {
    final cfg = config();
    if (!await requestAiConsent(
      context,
      cfg,
      'Será enviada mensagem "Responda apenas OK" usando plano ChatGPT. Conta pode consumir cota ou créditos conforme autorização concedida no ChatGPT. Nenhum dado de saúde será enviado.',
    )) {
      return;
    }
    if (cancel!.isCancelled) throw const AiFailure('Operação cancelada.');
    final answer = await ChatGptProvider(cfg).generate([
      {'role': 'user', 'content': 'Responda apenas OK'},
    ], cancel: cancel).join();
    if (answer.trim().isEmpty) {
      throw const AiFailure('Resposta concluída sem texto.');
    }
    if (mounted) {
      setState(
        () => status =
            'Geração concluída com plano ChatGPT para ${cfg.model}. Visão não testada.',
      );
    }
  });

  Future<void> save() => run(() async {
    final cfg = config();
    final account = accounts.firstWhere((a) => a['id'] == accountId);
    if (account['connected'] != true || account['enabled'] != true) {
      throw const AiFailure(
        'Conecte conta e autorize uso do plano antes de salvar.',
      );
    }
    final store = ref.read(storeProvider);
    await store.put('provider', cfg.toJson(), id: id);
    final tasks = await store.get('ai-tasks') ?? <String, dynamic>{};
    await store.put('settings', {...tasks, 'chat': id}, id: 'ai-tasks');
    if (mounted) Navigator.pop(context);
  });

  Future<void> logout() async {
    if (!await confirm(
      context,
      'Desconectar conta ChatGPT?',
      'Envios desta conta serão interrompidos. Configurações e registros locais serão mantidos. Nova conversa exigirá login novamente.',
      label: 'Desconectar',
    )) {
      return;
    }
    if (!mounted) return;
    await run(() async {
      final confirmed = await auth.signOut(accountId!);
      final list = await auth.accounts();
      if (mounted) {
        setState(() {
          accounts = list;
          status = confirmed ? 'Sessão desconectada e revogação confirmada.' : 'Tokens apagados neste aparelho. Revogação remota não confirmada; desconecte AI Fitness em https://chatgpt.com/settings/usage.';
        });
      }
    });
  }

  @override
  void dispose() {
    cancel?.cancel();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ChatGPT — assinatura'),
      actions: [
        if (widget.id != null)
          IconButton(
            tooltip: 'Excluir configuração',
            onPressed: busy
                ? null
                : () async {
                    if (!await confirm(
                      context,
                      'Excluir configuração?',
                      'Esta configuração será removida. Conta conectada poderá continuar sendo usada em outras configurações. Use Desconectar para revogar sessão.',
                      label: 'Excluir',
                    )) {
                      return;
                    }
                    if (!context.mounted) return;
                    await run(() async {
                      await ref.read(storeProvider).remove(id);
                      if (context.mounted) Navigator.pop(context);
                    });
                  },
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
    body: PageBody(
      title: 'Sua conta, seu plano.',
      subtitle: 'Login no navegador oficial',
      children: [
        const Text(
          'Use assinatura ChatGPT elegível, sem chave API e sem 9Router. Login e consentimento acontecem em auth.openai.com. Disponibilidade depende da OpenAI, conta e workspace. Cota é compartilhada com outros apps; créditos adicionais dependem das permissões dadas no ChatGPT. Não há troca automática para API paga.',
        ),
        const SizedBox(height: 20),
        if (accounts.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey(accountId),
            isExpanded: true,
            initialValue: accounts.any((a) => a['id'] == accountId)
                ? accountId
                : null,
            decoration: const InputDecoration(
              labelText: 'Conta / registro ChatGPT',
            ),
            items: accounts
                .map(
                  (a) => DropdownMenuItem<String>(
                    value: a['id'] as String,
                    child: Text(
                      '${a['email'] ?? 'Conta ChatGPT'} • ${accounts.indexOf(a) + 1}${a['connected'] == true ? '' : ' • desconectada'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (v) => setState(() {
                    accountId = v;
                    model = null;
                    models = [];
                    status = null;
                  }),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : () => login(add: accountId == null),
          child: const Text('Continuar com ChatGPT'),
        ),
        if (accounts.isNotEmpty)
          TextButton(
            onPressed: busy ? null : () => login(add: true),
            child: const Text('Adicionar outra conta ou workspace'),
          ),
        if (accountId != null)
          TextButton(
            onPressed: busy ? null : logout,
            child: const Text('Desconectar conta neste aparelho'),
          ),
        const SizedBox(height: 20),
        field(name, 'Nome desta configuração'),
        OutlinedButton(
          onPressed: busy || accountId == null ? null : discover,
          child: const Text('Descobrir modelos da conta'),
        ),
        if (models.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('$accountId-$model-${models.length}'),
            isExpanded: true,
            initialValue: models.contains(model) ? model : null,
            decoration: const InputDecoration(
              labelText: 'Modelo autorizado pelo catálogo',
            ),
            items: models
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(m, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: busy ? null : (v) => setState(() => model = v),
          ),
        ],
        SwitchListTile(
          title: const Text('Modelo aceita imagens'),
          subtitle: const Text(
            'Ative somente se modelo escolhido aceitar fotos.',
          ),
          value: images,
          onChanged: busy ? null : (v) => setState(() => images = v),
        ),
        const Text(
          'Este acesso exige streaming. Temperatura e limite de tokens não são enviados, conforme contrato da OpenAI.',
        ),
        if (status != null) Panel(child: SelectableText(status!)),
        if (busy) ...[
          const LinearProgressIndicator(),
          TextButton(
            onPressed: () => cancel?.cancel(),
            child: const Text('Cancelar'),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy || model == null ? null : test,
          child: const Text('Testar geração com ChatGPT'),
        ),
        FilledButton(
          onPressed: busy || model == null ? null : save,
          child: const Text('Salvar e usar no chat'),
        ),
        TextButton(
          onPressed: () async {
            try {
              await launchUrl(
                Uri.parse('https://chatgpt.com/settings/usage'),
                mode: LaunchMode.externalApplication,
              );
            } catch (_) {
              if (context.mounted) {
                notice(
                  context,
                  'Abra https://chatgpt.com/settings/usage no navegador.',
                );
              }
            }
          },
          child: const Text('Gerenciar acesso e limites no ChatGPT'),
        ),
      ],
    ),
  );
}
