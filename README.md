# AI Fitness

Licença: [MIT](LICENSE).

Aplicativo Android em Flutter para registrar alimentação, treino e evolução localmente, com IA opcional configurada pelo usuário. Registros locais não exigem conta ou assinatura. Sem telemetria. Idioma: português brasileiro.

**Versão em desenvolvimento: 1.6.5.** Catálogo de exercícios com busca bilíngue, demonstrações locais e GIFs online, cardio por GPS, alimentação por foto/texto, treinos por dia e foco muscular, evolução corporal e chat multiprovedor.

> O aplicativo não substitui acompanhamento médico, nutricional ou de educação física. Estimativas da IA podem estar erradas e precisam de revisão.

## Obter o projeto

```bash
git clone https://github.com/xFlocon/ai-fitness.git
cd ai-fitness
```

Código, documentação e testes estão neste repositório. APKs compilados, credenciais, bancos locais e dados pessoais não fazem parte do código versionado.

## Executar

Requer Flutter estável 3.50.1 / Dart 3.14, Java 21, Android SDK e licenças aceitas. Dependências resolvidas estão fixadas em `pubspec.lock`. Android mínimo: API 24.

```bash
flutter doctor -v
flutter doctor --android-licenses
flutter pub get
flutter analyze --fatal-infos
flutter test --reporter expanded
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`.

Configure caminhos da sua instalação, se ainda não estiverem disponíveis no terminal:

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"
```

Em alguns contêineres Linux, avisos Java sobre cgroup impedem Gradle de interpretar `jlink --version`. Se isso ocorrer, alternativa verificada, sem alterar Java global:

```bash
JAVA_TOOL_OPTIONS=-XX:-UseContainerSupport flutter build apk --release
```

O APK release usa **assinatura de desenvolvimento** gerada pelo template Flutter. É instalável, mas não adequado à publicação. Para distribuição comercial, configure keystore próprio fora do repositório e `signingConfigs` no arquivo `android/app/build.gradle.kts`. Não publique chaves de assinatura.

Instalação manual em aparelho autorizado:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

A compilação não instala automaticamente no aparelho conectado.

## Primeira utilização

1. Complete as cinco etapas do perfil. Campos opcionais podem ficar vazios.
2. Use Alimentação para registrar ingredientes. Informe nutrientes por 100 g e fonte consultada ou use IA para estimar porção e nutrientes a partir de texto/foto. Revise estimativas antes de tocar em **Já comi • registrar**.
3. Use Treinos para criar uma rotina manual, iniciar séries e registrar repetições e cargas.
4. Em Perfil, registre peso, observações e fotos opcionais. Fotos permanecem locais.
5. Configure IA somente se desejar os recursos remotos.

## Cardio — caminhada e pedalada

Abra **Cardio**, inicie caminhada ou pedalada e aguarde sinal GPS em área aberta. Permita localização precisa; passos dependem de sensor e permissão de atividade física. App mostra duração, distância, velocidades atual e média e, na caminhada, passos quando disponíveis.

Rastreamento continua ao trocar de aba ou bloquear tela, via serviço Android. Encerrar app pela lista de recentes ou forçar parada pode perder sessão não concluída. Ao terminar, resumo fica no histórico local; nenhuma coordenada é salva ou enviada. Calorias ativas são estimadas por peso, tempo total e velocidade média, sem medir relevo ou esforço individual. Sem dados suficientes, app não inventa estimativa.

## Configurar provedores

### Demonstrações de exercícios offline

Em **Treinos → Criar treino**, use **Adicionar do catálogo** para procurar por nome ou equipamento. Mídia local funciona sem internet. GIFs online são baixados do GitHub só ao tocar e reutilizados enquanto estiverem no cache. Nenhum deles exige chave. A IA seleciona IDs do catálogo sem receber arquivos. Links manuais e antigos são preservados. Veja [fontes, cobertura e licenças](docs/CATALOGO.md).

### YouTube opcional

No Google Cloud, ative a **YouTube Data API v3** e crie uma chave restrita a essa API. Cadastre em **Configurações → Vídeos de exercícios**. Chave fica no cofre local e não entra nas exportações. Campo vazio remove a chave e desativa a busca automática.

Com chave configurada, o app pesquisa vídeos públicos, incorporáveis e com menos de quatro minutos apenas para os exercícios sem demonstração local. Envia ao YouTube só os termos em português e inglês. Descarta compilações e incompatibilidades explícitas antes de a IA comparar até quatro candidatos por exercício por título, descrição e instruções, sem assistir aos vídeos. Se ainda faltar demonstração, o editor preserva a sugestão: adicione o link ou remova o exercício antes de salvar. Links de treinos salvos não mudam automaticamente.

Abra o exercício no editor ou na execução e toque **Carregar vídeo no app**. Player precisa de internet e se conecta ao YouTube somente após esse toque. Se faltar vídeo ou YouTube bloquear a reprodução, mantenha as instruções escritas, cole outro link no editor ou use **Abrir no YouTube**. Sem chave ou com cota esgotada, geração de treino continua funcionando.

### Treinos por dia e foco — versão 1.3.0

Em **Treinos → Criar treino**, selecione dias da semana e foco muscular. Exemplo: marque **Segunda + Braços**, gere ou cadastre exercícios e salve; depois crie outra rotina **Terça + Abdômen / barriga**. Vários dias na mesma rotina repetem a mesma sessão. Nenhum dia é obrigatório; treinos antigos continuam livres até você agendar.

Nome e campo **Preferências para IA** agora fazem parte da solicitação, junto de dias, foco, perfil e equipamentos. Ex.: “braços com halteres, 30 minutos”. IA sugere uma sessão por vez, não semana inteira numa geração. Nome vazio recebe nome padrão ao salvar. Lista de treinos mostra **Sua semana** e grupos de cada rotina; sessões continuam iniciadas manualmente.

Corrigido contrato de descanso: IA recebe limites e unidade explícitos (10–600 segundos, inteiros). Descanso ausente ou zero vindo da IA recebe **60 s**, informado na revisão; valores fora do intervalo ou com unidade ambígua não são adivinhados. Erro agora identifica exercício e campo, em vez de somente “Informe um número entre 10.0 e 600.0”. Carga inicial gerada é sempre zero; séries e repetições devem ser inteiras. Execução atual usa repetições, não isometrias cronometradas; geração pede exercícios compatíveis.

Agenda não garante recuperação suficiente nem substitui prescrição profissional. Abdômen fortalece região, sem promessa de perda de gordura localizada. Bloqueios de geração por idade, gestação, condições clínicas e limitações continuam ativos. Sem lembretes recorrentes ou alteração automática da rotina.

### Correção 1.2.1 — registrar refeição sem nome

Nome da refeição agora é opcional. Se ficar vazio ou somente com espaços, registro usa categoria selecionada (ex.: Almoço ou Lanche), inclusive ao salvar favorita. Nome informado continua preservado; acima de 120 caracteres, mensagem identifica campo e limite. Corrige erro genérico “Texto ausente ou muito longo” ao registrar estimativas sem preencher nome.

### Estimativa de refeições — versão 1.2.0

Em **Alimentação → Registrar ou analisar refeição**, descreva algo como “uma coxinha média” ou anexe fotografia JPEG e toque **Estimar porção e nutrientes com IA**. Selecione previamente provedor/modelo da tarefa **Visão** nas configurações de IA; para fotos, modelo precisa aceitar imagens. Texto também funciona sem foto.

A IA sugere peso total da porção e valores médios por 100 g: calorias, proteínas, carboidratos, gorduras e fibras. Por exemplo, pode assumir uma unidade de 100 g, mas esse peso não é fixo nem medido: depende da descrição e hipótese do modelo. Calorias da porção são calculadas localmente com `gramas / 100`; editar peso recalcula os totais.

Resultados entram no editor sem pedir preenchimento manual de nutrientes e sem gravar diário. Cada alimento mostra **Estimativa da IA**, preparo/porção assumidos e limitações. Use lápis para corrigir. Apenas **Já comi • registrar** salva refeição. Origem e observações ficam no registro, favoritas e exportação; diário identifica refeições com estimativas. Para substituir por valores verificados, edite nutrientes, desmarque **Mantém valores estimados pela IA** e atualize fonte consultada.

Estimativas não equivalem a análise laboratorial ou consulta a tabela/rótulo. Tamanho, receita, recheio e óleo podem mudar bastante os valores. Validação bloqueia campos ausentes, valores não finitos/negativos e algumas inconsistências, mas **não comprova precisão nutricional**. Modelo não deve inventar fonte verificada. Registro manual continua disponível sem IA. Não há novas metas ou prescrições clínicas automáticas.

### Correções 1.1.1

- Mensagens do chat usam cores explícitas do tema para texto, títulos, listas, tabelas, citações e código. Texto normal não recebe negrito; marcações Markdown continuam preservadas. Correção também vale para conversas salvas.
- No próximo envio, **Lembrar para todos os envios de IA** vem marcado. Ao tocar **Autorizar envio**, permissão fica salva neste aparelho para todos os recursos e provedores, inclusive testes, fotos anexadas e dados de saúde selecionados. Não há nova confirmação enquanto autorização estiver ativa.
- Para autorizar somente uma vez, desmarque **Lembrar**. Cancelar ou fechar diálogo não salva autorização. Para revogar, abra **Configurações → Privacidade → Autorização geral de IA → Revogar**.
- Autorização não seleciona contexto, anexa fotos, inicia envios em segundo plano nem libera outros registros. Login OAuth, permissões Android, exportação e exclusão mantêm suas próprias confirmações.

### ChatGPT Plus/Pro — login direto (versão 1.1.0)

Esta opção usa o fluxo oficial **Sign in with ChatGPT** para projetos locais elegíveis, não a chave da API nem credenciais do 9Router.

1. Instale atualização sobre versão existente, sem desinstalar.
2. Abra **Perfil → Inteligência Artificial → Entrar com ChatGPT — usar assinatura**.
3. Toque **Continuar com ChatGPT**. Navegador abre `https://auth.openai.com`; confira domínio antes de entrar. Senha nunca é digitada no AI Fitness.
4. Autorize registro AI Fitness e uso do plano. Retorno usa listener temporário `127.0.0.1` no próprio telefone. Volte ao app se navegador não fizer isso automaticamente. Login expira após cinco minutos; mantenha app aberto/em segundo plano sem encerrá-lo.
5. Use **Descobrir modelos da conta** e escolha modelo listado. Depois use **Testar geração com ChatGPT**.
6. Toque **Salvar e usar no chat**. Conversação passa para essa configuração. Visão e planejamento podem ser associados à mesma configuração na tela de provedores.

Cota é compartilhada conforme plano; app também pode ter limite próprio. Permissão de usar créditos após limite é administrada no ChatGPT, não implica gratuidade ilimitada. Não há fallback automático para chave API paga. Modelos disponíveis vêm do catálogo OAuth da conta.

Tokens e email ficam em armazenamento seguro Android, separados por registro/conta, sem exportação ou logs. PKCE S256, `state`, `nonce`, assinatura RS256/JWKS, emissor, audience, expiração e identidade são validados. Renovação serializada evita corrida de refresh tokens rotativos. **Desconectar** interrompe envios, tenta revogar sessão e remove tokens locais; sem confirmação de revogação, remova acesso em <https://chatgpt.com/settings/usage>. Registro e host ID são retidos para reautorização até exclusão total dos dados.

Requests usam exclusivamente `POST https://api.openai.com/v1/responses`, `store:false`, `stream:true`, sem temperatura ou limite de saída não suportados. Instruções vão em `instructions`. Texto parcial não confirma sucesso: exige evento `response.completed`. Ferramentas e recursos não permitidos não são enviados.

**Disponibilidade:** usuário confirmou funcionamento do login no aparelho. Testes automatizados usam servidor loopback real e autenticação/inferência simuladas com assinatura criptográfica de teste; não validam disponibilidade para todas as contas. Login pode ser recusado por elegibilidade, workspace, região ou disponibilidade do fluxo de registro. Nesse caso, app informa falha e não troca cobrança. Não há promessa de equivalência exata ao acesso interno usado pelo 9Router.

Contrato consultado: [registro e login](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [inferência](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference), [limitações](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).

### Provedores com chave API

1. Abra **Perfil → Inteligência Artificial → Adicionar provedor / modelo**.
2. Escolha protocolo, nome, URL base, chave e ID exato do modelo. A URL deve incluir o prefixo da API, mas não o endpoint de geração.
3. Configure imagens e streaming conforme capacidades reais do modelo. A opção de ferramentas é apenas uma declaração de capacidade; execução automática ainda não existe.
4. Use **Descobrir modelos** quando disponível. Informe um ID inicial para validar o formulário; o resultado pode substituí-lo.
5. Use **Testar conexão**. Isso faz uma geração de texto, não testa visão ou ferramentas, e pode gerar cobrança.
6. Salve e selecione configurações separadas para conversação, visão e planejamento. Para usar modelos diferentes no mesmo servidor, crie configurações adicionais.

| Provedor | URL base padrão | Protocolo |
|---|---|---|
| OpenAI | `https://api.openai.com/v1` | Chat Completions |
| 9Router | `http://localhost:20128/v1` | Chat Completions |
| OpenRouter | `https://openrouter.ai/api/v1` | Chat Completions |
| Gemini | `https://generativelanguage.googleapis.com/v1beta` | generateContent / streamGenerateContent |
| Claude | `https://api.anthropic.com/v1` | Messages |
| Ollama | `http://localhost:11434/api` | chat / tags nativos |
| LM Studio | `http://localhost:1234/v1` | Chat Completions |
| Personalizado | URL configurada pelo usuário | Compatível OpenAI |

No Android, `localhost` é o próprio telefone. Para servidor no computador, use IP da rede, como `http://192.168.1.10:11434/api`. No emulador Android, `10.0.2.2` aponta para o computador hospedeiro.

**HTTP local não usa criptografia.** Exige autorização explícita por configuração. O cliente aceita apenas IPv4 privado literal, loopback ou localhost; bloqueia endereços públicos, URLs com credenciais, query ou fragmento e não segue redirecionamentos. Android não expressa intervalos privados dinâmicos no XML, portanto a política de cleartext da plataforma é aberta e a restrição é aplicada pelo único cliente HTTP em `AiConfig.validateUrl`. Novos clientes devem reutilizar essa validação. Prefira HTTPS até na rede local.

Não exponha portas de Ollama/LM Studio à internet. Modelos que exigem Responses API, parâmetros específicos ou protocolos diferentes de OpenAI não são automaticamente compatíveis. Temperatura e limite de tokens podem ser recusados por certos modelos.

## O que funciona

- Material Design 3, tema escuro/claro/automático, cores, redução de movimento e navegação com seis abas.
- Onboarding em etapas e edição posterior do perfil.
- SQLite real por Drift, sem servidor para registros locais.
- Diário por data e categoria; edição, exclusão e refeições favoritas.
- Ingredientes com porções em gramas, referência nutricional explícita e soma determinística de energia, macros e fibras.
- Fotografia JPEG por câmera/galeria ou descrição textual; envio consentido, estimativa de porção e nutrientes em JSON validado e revisão no editor antes de registrar.
- Estimativa Mifflin-St Jeor, margens conservadoras, metas manuais e bloqueios para menores, gestantes e necessidades clínicas.
- Rotinas manuais e propostas de IA revisáveis; instruções, segurança, alternativas, carga, séries, repetições e descanso.
- Execução com séries persistidas, carga/repetições realizadas, descanso, pausa/retomada, substituição e histórico.
- Proposta de progressão de carga após duas sessões consistentes; confirmação e salvamento explícitos.
- Chat com streaming, Markdown, imagens, histórico local, cancelamento e regeneração; contexto selecionável e limitado.
- Planejador culinário com preferências, restrições, orçamento e alimentos disponíveis; sugestões salvas e lista de compras editável.
- Peso editável, observações/medidas textuais, gráficos por período e fotos locais com comparação deslizante, lado a lado e zoom.
- Gráficos de calorias, proteínas, sessões, cargas máximas diárias e dias com registros.
- Lembretes locais configuráveis por categoria para a próxima ocorrência do horário escolhido.
- Exportação JSON sem chaves, provedores, chats e caminhos de fotos; exclusão local; política de privacidade e licenças dentro do app.

## Limites e pendências

- **TBCA/TACO não estão incorporadas nem consultadas automaticamente.** É necessário obter autorização/licença e dados versionados antes de redistribuir. IA pode estimar nutrientes sem fonte verificada; esses valores são rotulados como estimativas, não como dados consultados. Usuário pode substituir por rótulo ou fonte conhecida.
- Fotografia não determina peso real, óleos, ingredientes ocultos ou preparo. A ferramenta apresenta estimativas corrigíveis, não medição clínica.
- Health Connect não implementado. Nenhuma permissão de saúde é solicitada.
- Ferramentas nativas de IA, function calling e propostas estruturadas dentro do chat ainda pendentes. Chat nunca executa comandos nem altera diário.
- Limitações/lesões, condições clínicas, gestação e menoridade bloqueiam geração automática de treino; rotina profissional pode ser cadastrada manualmente. Não existe validador clínico de exercícios.
- Progressão determinística não avalia técnica, dor ou recuperação. Não implica recomendação clínica.
- Lembretes são avulsos, não recorrentes. Preferência salva não prova entrega; Android pode atrasar alarmes e o registro de preferência não é limpo automaticamente após entrega. Reagendamento após reinício e mudança de fuso pendentes.
- Medidas corporais são observações em texto, não séries numéricas separadas por região.
- Fotos de refeições são usadas no envio corrente, mas não são anexadas ao histórico. Só fotos corporais possuem coleção local persistente.
- Registros usam unidades métricas; conversão imperial e categorias de refeição criadas pelo usuário pendentes.
- Sem base alimentar offline pré-carregada, catálogo de exercícios, inferência de IA no telefone, sincronização ou importação de backup. Login opcional existe apenas para integração ChatGPT, não para sincronizar registros do app.
- Banco SQLite não tem criptografia própria; depende da proteção do Android. Chaves usam armazenamento seguro. Backup automático do Android está desativado. Apagamento não garante remoção forense de blocos em flash.
- Fotos corporais locais não são exportadas; chats não são exportados. Arquivos exportados ficam fora do controle do app e contêm dados sensíveis.
- Sem revisão jurídica LGPD ou publicação em loja. Privacidade informa fluxo real, não certifica conformidade legal.
- Português brasileiro configurado com localizações Material; textos ainda precisam ser extraídos para ARB para adicionar outros idiomas.
- Interface usa estados reais de carregamento e animações pontuais; skeletons, transições especiais, marca/ícone final e auditoria completa TalkBack pendentes.
- APIs reais, câmera, cofre Android, alarmes e compartilhamento exigem validação em aparelho. Não foram aprovados por teste de widget.
- Sem ajuste automático de metas pelo peso recente; perfil e meta são editáveis. Gráficos não alegam mudança de gordura ou massa muscular.
- `share_plus` ainda emite aviso de migração futura do Kotlin Gradle Plugin; build atual é compatível.

## Estrutura

```text
lib/
  app/                         # tema, Riverpod, GoRouter e shell
  core/                        # modelos, regras, Drift, HTTP IA e lembretes
  features/
    onboarding/
    dashboard/
    nutrition/                 # diário, editor e planejador
    food_analysis/
    workouts/
    ai_assistant/
    body_progress/
    statistics/
    profile/
    settings/
  shared/                      # componentes e diálogos comuns
test/                          # domínio, SQLite, protocolos, navegação e layout
docs/                          # status e capturas produzidas por testes
```

Arquitetura modular enxuta: regras sem dependência de IA em `core/models.dart`; contrato `AiProvider`; segredos em `KeyVault`; estado e invalidação com Riverpod. Drift usa documentos JSON versionados em SQLite com índice por tipo. Comentários `ponytail:` documentam simplificações e limites. Não há gerador de código de banco.

## Testes

```bash
flutter test --reporter expanded
dart analyze --format=machine lib test
```

Cobertura de comportamentos: cálculos e bloqueios; refeições, atualização de macros e exclusão; peso; criação/edição de treino; persistência após reabrir arquivo; provedores e política de URL; JSON malformado; erros de autenticação; streaming UTF-8 fragmentado; descoberta e resposta não streaming; planejamento; navegação; layout estreito.

Fixtures são dados de teste identificados e não são carregadas pelo aplicativo. Consulte `docs/STATUS.md` para resultados finais da execução e compilação.
