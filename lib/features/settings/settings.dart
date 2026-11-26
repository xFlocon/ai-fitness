import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ai.dart';
import '../../core/chatgpt.dart';
import '../../core/models.dart';
import '../../core/store.dart';
import '../../core/reminders.dart';
import '../../shared/ui.dart';
import '../food_analysis/analysis.dart';
import '../workouts/exercise_video.dart';
import 'chatgpt_settings.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(changesProvider);
    final store = ref.read(storeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: PageBody(
        title: 'Do seu jeito.',
        subtitle: 'Controle e privacidade',
        children: [
          Load(
            future: store
                .get('appearance')
                .then((v) => v ?? <String, dynamic>{}),
            builder: (appearance) => Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aparência',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: appearance['mode'] as String? ?? 'dark',
                    decoration: const InputDecoration(labelText: 'Tema'),
                    items: const [
                      DropdownMenuItem(value: 'dark', child: Text('Escuro')),
                      DropdownMenuItem(value: 'light', child: Text('Claro')),
                      DropdownMenuItem(
                        value: 'system',
                        child: Text('Automático'),
                      ),
                    ],
                    onChanged: (v) => store.put('settings', {
                      ...appearance,
                      'mode': v,
                    }, id: 'appearance'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reduzir movimento'),
                    subtitle: const Text(
                      'Preferência do Android também é respeitada.',
                    ),
                    value: appearance['reduceMotion'] == true,
                    onChanged: (v) => store.put('settings', {
                      ...appearance,
                      'reduceMotion': v,
                    }, id: 'appearance'),
                  ),
                  Wrap(
                    spacing: 12,
                    children: [0xffa3ff6f, 0xff65b8ff, 0xffffc67a, 0xffd2a8ff]
                        .map(
                          (color) => IconButton(
                            tooltip: 'Cor ${color.toRadixString(16)}',
                            onPressed: () => store.put('settings', {
                              ...appearance,
                              'color': color,
                            }, id: 'appearance'),
                            icon: Icon(
                              Icons.circle,
                              color: Color(color),
                              size: 32,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          Panel(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.ondemand_video_outlined),
                  title: const Text('Vídeos de exercícios'),
                  subtitle: const Text(
                    'Chave do YouTube para buscar termos de exercícios automaticamente',
                  ),
                  onTap: () => configureExerciseVideos(context),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('Inteligência Artificial'),
                  subtitle: const Text('Provedores, modelos e chaves'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/providers'),
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_none),
                  title: const Text('Notificações'),
                  subtitle: const Text('Preferências de lembretes'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ReminderPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privacidade',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Dados locais por padrão. Nenhuma telemetria. Você pode autorizar uma vez todos os envios de IA e revogar abaixo. Apenas conteúdo solicitado e contexto selecionado são enviados. Chaves e tokens opcionais de login ChatGPT ficam no armazenamento seguro do Android, fora da exportação. O banco local não possui criptografia própria; use bloqueio de tela e criptografia do aparelho.',
                ),
                Load(
                  future: store
                      .get('ai-consent')
                      .then((v) => v ?? <String, dynamic>{}),
                  builder: (consent) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.verified_user_outlined),
                    title: const Text('Autorização geral de IA'),
                    subtitle: Text(
                      consent['remember'] == true
                          ? 'Ativa para todos os recursos e provedores. Toque para voltar a confirmar envios.'
                          : 'Inativa. Autorize e marque “Lembrar” no próximo envio de IA.',
                    ),
                    trailing: consent['remember'] == true
                        ? const Text('Revogar')
                        : null,
                    onTap: consent['remember'] == true
                        ? () async {
                            try {
                              await store.remove('ai-consent');
                              if (context.mounted) {
                                notice(
                                  context,
                                  'Autorização revogada. Próximos envios pedirão confirmação.',
                                );
                              }
                            } catch (e) {
                              if (context.mounted) notice(context, apiError(e));
                            }
                          }
                        : null,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Exportar histórico em JSON'),
                  subtitle: const Text(
                    'Sem chaves, provedores, chats ou fotografias.',
                  ),
                  onTap: () async {
                    try {
                      if (!await confirm(
                        context,
                        'Exportar dados de saúde?',
                        'O arquivo conterá perfil, alimentação, peso e treinos. Ele não será criptografado. Compartilhe somente com pessoas e aplicativos confiáveis.',
                        label: 'Exportar',
                      )) {
                        return;
                      }
                      final dir = await getTemporaryDirectory();
                      final file = File(
                        '${dir.path}/ai-fitness-${DateTime.now().millisecondsSinceEpoch}.json',
                      );
                      await file.writeAsString(
                        const JsonEncoder.withIndent('  ')
                            .convert(await store.export()),
                        flush: true,
                      );
                      await SharePlus.instance.share(
                        ShareParams(
                          files: [XFile(file.path)],
                          text: 'Histórico AI Fitness',
                        ),
                      );
                    } catch (e) {
                      if (context.mounted) notice(context, apiError(e));
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Política de privacidade'),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Privacidade • versão 3'),
                      content: const SingleChildScrollView(
                        child: Text(
                          'AI Fitness funciona sem conta para registros locais. Dados de alimentação, perfil, peso, treino e fotos são tratados localmente para oferecer acompanhamento. Não há anúncios, rastreamento ou servidor próprio.\n\nProvedores de IA são escolhidos por você. Ao autorizar envio, o provedor recebe somente o conteúdo descrito no diálogo. Consulte a política dele; apagar dados locais não apaga dados já enviados.\n\nLogin ChatGPT é opcional e abre navegador oficial da OpenAI. Após consentimento, identificador da conta, email, registro e tokens ficam no armazenamento seguro deste aparelho. Não recebemos sua senha. Tokens não entram em exportações. Desconectar tenta revogar sessão; sem confirmação remota, remova acesso em chatgpt.com/settings/usage. Uso do plano e possíveis créditos seguem permissões escolhidas no ChatGPT.\n\nVocê pode corrigir registros, exportar histórico e excluir tudo neste aparelho. Fotos não são incluídas na exportação. Arquivos exportados e cópias feitas fora do aplicativo ficam sob seu controle.\n\nDados de saúde são sensíveis conforme LGPD. Não envie dados de terceiros. Desinstalar ou excluir não garante remoção forense de blocos em memória flash. Use criptografia do Android. O app não substitui assistência clínica.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Fechar'),
                        ),
                      ],
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  textColor: Theme.of(context).colorScheme.error,
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Excluir todos os dados'),
                  onTap: () async {
                    if (!await confirm(
                      context,
                      'Excluir tudo permanentemente?',
                      'Perfil, refeições, treinos, chats, fotos locais e chaves serão removidos deste aplicativo. Não será possível desfazer. Exportações externas e dados já enviados a provedores não serão apagados.',
                      label: 'Excluir tudo',
                    )) {
                      return;
                    }
                    try {
                      await ReminderService.cancelAll();
                      final revoked = await ChatGptAuth.instance.signOutAll();
                      await const KeyVault().clear();
                      final dir = Directory(
                        '${(await getApplicationSupportDirectory()).path}/photos',
                      );
                      if (await dir.exists()) {
                        for (final file in dir.listSync().whereType<File>()) {
                          await file.delete();
                        }
                      }
                      await store.erase();
                      if (context.mounted) {
                        if (!revoked) {
                          notice(
                            context,
                            'Dados locais removidos. Revogação ChatGPT não confirmada; remova acesso em chatgpt.com/settings/usage.',
                          );
                        }
                        context.go('/onboarding');
                      }
                    } catch (e) {
                      if (context.mounted) notice(context, apiError(e));
                    }
                  },
                ),
              ],
            ),
          ),
          Panel(
            child: Column(
              children: [
                const ListTile(
                  title: Text('AI Fitness'),
                  subtitle: Text('1.6.6 • acompanhamento local; IA opcional'),
                ),
                ListTile(
                  title: const Text('Licenças de código aberto'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'AI Fitness',
                    applicationVersion: '1.6.6',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProvidersPage extends ConsumerWidget {
  const ProvidersPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(changesProvider);
    final store = ref.read(storeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Inteligência Artificial')),
      body: PageBody(
        title: 'Escolha sua IA.',
        subtitle: 'Sem fornecedor obrigatório',
        children: [
          const Text(
            'Configure um provedor por modelo. Você pode repetir o mesmo servidor com modelos diferentes. Nenhuma chamada é feita ao salvar.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.push('/provider'),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar provedor / modelo'),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const ChatGptSettingsPage(),
              ),
            ),
            icon: const Icon(Icons.login),
            label: const Text('Entrar com ChatGPT — usar assinatura'),
          ),
          const SizedBox(height: 20),
          Load(
            future: Future.wait([
              store.list('provider'),
              store.get('ai-tasks'),
            ]),
            builder: (result) {
              final providers = result[0] as List<Record>;
              final tasks = result[1] as Json? ?? {};
              return Column(
                children: [
                  if (providers.isEmpty)
                    const EmptyState(
                      'Sua IA, suas regras',
                      'OpenAI, Gemini, Claude, 9Router e servidores locais. Adicione suas credenciais para começar.',
                    ),
                  ...providers.map(
                    (p) => Panel(
                      onTap: () => p.data['type'] == chatGptType
                          ? Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ChatGptSettingsPage(id: p.id),
                              ),
                            )
                          : context.push('/provider?id=${p.id}'),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${p.data['name']}'),
                        subtitle: Text(
                          '${p.data['type']} • ${p.data['model']}',
                        ),
                        trailing: const Icon(Icons.edit_outlined),
                      ),
                    ),
                  ),
                  if (providers.isNotEmpty)
                    Panel(
                      child: Column(
                        children: ['chat', 'vision', 'planning']
                            .map(
                              (task) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey('$task-${tasks[task]}'),
                                  isExpanded: true,
                                  initialValue:
                                      providers.any((p) => p.id == tasks[task])
                                      ? tasks[task] as String
                                      : null,
                                  decoration: InputDecoration(
                                    labelText: {
                                      'chat': 'Conversação',
                                      'vision': 'Visão e alimentos',
                                      'planning': 'Planejamento',
                                    }[task],
                                  ),
                                  items: providers
                                      .map(
                                        (p) => DropdownMenuItem(
                                          value: p.id,
                                          child: Text(
                                            '${p.data['name']} • ${p.data['model']}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => store.put('settings', {
                                    ...tasks,
                                    task: v,
                                  }, id: 'ai-tasks'),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              );
            },
          ),
          const Text(
            'Android: localhost aponta para o próprio celular. Para Ollama ou LM Studio no computador, use IP privado da rede. No emulador Android, 10.0.2.2 alcança o computador hospedeiro. Não exponha portas de IA à internet.',
          ),
        ],
      ),
    );
  }
}

class ProviderEditor extends ConsumerStatefulWidget {
  final String? id;
  const ProviderEditor({super.key, this.id});
  @override
  ConsumerState<ProviderEditor> createState() => _ProviderState();
}

class _ProviderState extends ConsumerState<ProviderEditor> {
  final c = List.generate(7, (_) => TextEditingController());
  String type = providerTypes.first;
  bool images = false,
      tools = false,
      streaming = true,
      localHttp = false,
      busy = false;
  late String id;
  CancelToken? cancel;
  String? status;
  @override
  void initState() {
    super.initState();
    id = widget.id ?? ref.read(storeProvider).newId();
    c[1].text = providerUrls.first;
    c[4].text = '0.4';
    c[5].text = '2048';
    c[6].text = '60';
    _load();
  }

  Future<void> _load() async {
    if (widget.id == null) return;
    try {
      final data = await ref.read(storeProvider).get(id);
      if (data == null) return;
      final cfg = AiConfig.fromJson(data);
      final key = await const KeyVault().read(id);
      if (!mounted) return;
      setState(() {
        type = cfg.type;
        images = cfg.images;
        tools = cfg.tools;
        streaming = cfg.streaming;
        localHttp = cfg.localHttp;
        final values = [
          cfg.name,
          cfg.baseUrl,
          key,
          cfg.model,
          '${cfg.temperature}',
          '${cfg.tokens}',
          '${cfg.timeout}',
        ];
        for (var i = 0; i < c.length; i++) {
          c[i].text = values[i];
        }
      });
    } catch (e) {
      if (mounted) setState(() => status = apiError(e));
    }
  }

  AiConfig config(String op) {
    final name = c[0].text.trim();
    final model = c[3].text.trim();
    if (op != 'models' && model.isEmpty) {
      throw const FormatException(
        'Informe o ID do modelo ou toque em Descobrir modelos.',
      );
    }
    if (op == 'save' && name.isEmpty) {
      throw const FormatException(
        'Preencha Nome desta configuração antes de salvar.',
      );
    }
    final cfg = AiConfig(
      id: id,
      name: name.isEmpty ? type : text(name, max: 100),
      type: type,
      baseUrl: text(c[1].text),
      model: op == 'models' ? '' : text(model, max: 200),
      temperature: op == 'models' ? .4 : number(c[4].text, max: 2),
      tokens: op == 'models'
          ? 2048
          : number(c[5].text, min: 128, max: 32768).round(),
      timeout: number(c[6].text, min: 5, max: 300).round(),
      images: images,
      tools: tools,
      streaming: streaming,
      localHttp: localHttp,
    );
    cfg.validateUrl();
    return cfg;
  }

  Future<void> action(String op) async {
    try {
      final cfg = config(op);
      if (op == 'save') {
        setState(() => busy = true);
        await const KeyVault().write(id, c[2].text.trim());
        await ref.read(storeProvider).put('provider', cfg.toJson(), id: id);
        if (mounted) context.pop();
        return;
      }
      if (!await requestAiConsent(
        context,
        cfg,
        op == 'models'
            ? 'Será feita uma consulta de modelos com a chave informada. Nenhum dado de saúde será enviado.'
            : 'Será enviada a mensagem de teste "Responda apenas OK" com a chave informada. Nenhum dado de saúde será enviado.',
      )) {
        return;
      }
      if (!mounted) return;
      setState(() {
        busy = true;
        status = null;
      });
      cancel = CancelToken();
      final provider = HttpAiProvider(cfg, c[2].text.trim());
      if (op == 'models') {
        final models = await provider.models(cancel: cancel);
        if (!mounted) return;
        final selected = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Modelos disponíveis'),
            children: models
                .map(
                  (m) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, m),
                    child: Text(m),
                  ),
                )
                .toList(),
          ),
        );
        if (selected != null) c[3].text = selected;
        status = '${models.length} modelos encontrados.';
      } else {
        var answer = '';
        await for (final part in provider.generate([
          {'role': 'user', 'content': 'Responda apenas OK'},
        ], cancel: cancel)) {
          answer += part;
        }
        if (answer.trim().isEmpty) {
          throw const AiFailure('Servidor respondeu, mas não retornou texto.');
        }
        status =
            'Conexão, autenticação e geração de texto validadas para ${cfg.model}. Visão e ferramentas não foram testadas.';
      }
    } catch (e) {
      status = apiError(e);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() {
    cancel?.cancel();
    for (final x in c) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Provedor / modelo'),
      actions: [
        if (widget.id != null)
          IconButton(
            tooltip: 'Excluir provedor',
            icon: const Icon(Icons.delete_outline),
            onPressed: busy
                ? null
                : () async {
                    if (!await confirm(
                      context,
                      'Excluir provedor?',
                      'A chave e esta configuração serão removidas. Selecione outro modelo para as tarefas vinculadas.',
                      label: 'Excluir',
                    )) {
                      return;
                    }
                    try {
                      await const KeyVault().delete(id);
                      await ref.read(storeProvider).remove(id);
                      if (context.mounted) context.pop();
                    } catch (e) {
                      if (context.mounted) notice(context, apiError(e));
                    }
                  },
          ),
      ],
    ),
    body: PageBody(
      title: 'Conexão sob controle.',
      subtitle: 'Chave protegida no Android',
      children: [
        DropdownButtonFormField<String>(
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Protocolo / provedor'),
          items: providerTypes
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: busy
              ? null
              : (v) => setState(() {
                  type = v!;
                  c[1].text = providerUrls[providerTypes.indexOf(type)];
                }),
        ),
        const SizedBox(height: 16),
        field(c[0], 'Nome desta configuração'),
        field(c[1], 'URL base completa (inclua /v1 ou /api)'),
        field(c[2], 'Chave de API (opcional no servidor local)', secret: true),
        field(c[3], 'ID exato do modelo'),
        OutlinedButton(
          onPressed: busy ? null : () => action('models'),
          child: const Text('Descobrir modelos'),
        ),
        const SizedBox(height: 16),
        field(c[4], 'Temperatura (0–2)', numeric: true),
        field(c[5], 'Limite de tokens (128–32768)', numeric: true),
        field(c[6], 'Timeout em segundos (5–300)', numeric: true),
        SwitchListTile(
          title: const Text('Modelo aceita imagens'),
          value: images,
          onChanged: (v) => setState(() => images = v),
        ),
        SwitchListTile(
          title: const Text('Modelo aceita ferramentas'),
          subtitle: const Text(
            'Capacidade declarada. Chamadas automáticas ainda não são executadas.',
          ),
          value: tools,
          onChanged: (v) => setState(() => tools = v),
        ),
        SwitchListTile(
          title: const Text('Streaming'),
          value: streaming,
          onChanged: (v) => setState(() => streaming = v),
        ),
        SwitchListTile(
          title: const Text('Autorizar HTTP somente na rede local'),
          subtitle: const Text(
            'Sem criptografia; somente IPs privados literais ou localhost. APIs remotas exigem HTTPS.',
          ),
          value: localHttp,
          onChanged: (v) async {
            if (!v ||
                await confirm(
                  context,
                  'Permitir conexão sem criptografia?',
                  'HTTP pode expor mensagens, imagens e chave a pessoas na mesma rede. Use somente servidor e rede confiáveis. O aplicativo continuará bloqueando HTTP para endereços públicos.',
                  label: 'Permitir HTTP local',
                )) {
              if (mounted) setState(() => localHttp = v);
            }
          },
        ),
        if (status != null) Panel(child: Text(status!)),
        if (busy) ...[
          const LinearProgressIndicator(),
          TextButton(
            onPressed: () => cancel?.cancel(),
            child: const Text('Cancelar conexão'),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: busy ? null : () => action('test'),
          icon: const Icon(Icons.wifi_tethering),
          label: const Text('Testar conexão'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : () => action('save'),
          child: const Text('Salvar configuração'),
        ),
      ],
    ),
  );
}

class ReminderPage extends ConsumerStatefulWidget {
  const ReminderPage({super.key});
  @override
  ConsumerState<ReminderPage> createState() => _ReminderState();
}

class _ReminderState extends ConsumerState<ReminderPage> {
  @override
  Widget build(BuildContext context) {
    ref.watch(changesProvider);
    final store = ref.read(storeProvider);
    const categories = [
      'Treino',
      'Registro alimentar',
      'Acompanhamento',
      'Revisão de metas',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Lembretes')),
      body: PageBody(
        title: 'Um toque de cuidado.',
        subtitle: 'Você escolhe quando',
        children: [
          const Text(
            'Agende um lembrete para a próxima ocorrência do horário escolhido. Não há repetição automática. Toque no horário para reagendar.',
          ),
          const SizedBox(height: 20),
          Load(
            future: store
                .get('reminders')
                .then((v) => v ?? <String, dynamic>{}),
            builder: (prefs) => Column(
              children: categories.indexed.map((pair) {
                final key = '${pair.$1}';
                final item = prefs[key] as Json?;
                Future<void> schedule() async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 18, minute: 0),
                  );
                  if (time == null) return;
                  try {
                    await ReminderService.schedule(
                      pair.$1,
                      pair.$2,
                      time.hour,
                      time.minute,
                    );
                    await store.put('settings', {
                      ...prefs,
                      key: {'hour': time.hour, 'minute': time.minute},
                    }, id: 'reminders');
                  } catch (e) {
                    if (context.mounted) notice(context, '$e');
                  }
                }

                return Panel(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(pair.$2),
                    subtitle: Text(
                      item == null
                          ? 'Desativado'
                          : 'Próximo lembrete: ${TimeOfDay(hour: item['hour'] as int, minute: item['minute'] as int).format(context)} • toque para alterar',
                    ),
                    value: item != null,
                    onChanged: (enabled) async {
                      if (enabled) {
                        await schedule();
                      } else {
                        try {
                          await ReminderService.cancel(pair.$1);
                          final next = {...prefs}..remove(key);
                          await store.put('settings', next, id: 'reminders');
                        } catch (e) {
                          if (context.mounted) notice(context, '$e');
                        }
                      }
                    },
                    secondary: IconButton(
                      tooltip: 'Escolher horário',
                      onPressed: schedule,
                      icon: const Icon(Icons.schedule),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
