# Estado de entrega

## Etapa 1 — Fundação
Implementados projeto Android, módulos, tema, navegação, Riverpod e SQLite/Drift. Banco testado em memória e arquivo real, inclusive fechamento/reabertura.

## Etapa 2 — Interface
Implementados onboarding, dashboard, alimentação, treinos, chat e perfil. Navegação testada por widgets, incluindo redução de movimento ativada. Overflow encontrado em 320 px corrigido e teste aprovado. Captura em `docs/screenshots/dashboard-test.png` usa perfil de teste, sem preencher banco do aplicativo.

## Etapa 3 — IA
Adaptadores HTTP, cofre, configuração por tarefa, descoberta, teste de conexão, streaming, consentimento e cancelamento implementados. Protocolos testados com respostas HTTP simuladas; sem chamadas autenticadas reais.

## Etapa 4 — Nutrição
Diário, porções, macros, metas e identificação multimodal implementados. Nutrientes precisam ser informados de fonte consultada. Integração automática TBCA/TACO pendente por dados e licença. Fluxos clínicos bloqueiam metas automáticas.

## Etapa 5 — Treinamento
Rotinas, proposta de IA, execução, pausa/retomada, substituições, histórico e proposta conservadora de progressão implementados. Persistência e validação testadas; sem validação clínica ou teste de treinamento real em aparelho.

## Etapa 6 — Evolução
Peso, observações, fotos privadas, comparação e gráficos implementados. Persistência de peso testada. Galeria, zoom e comparação precisam de validação visual em dispositivo.

## Etapa 7 — Finalização
Compilação release usa Java 21 e `JAVA_TOOL_OPTIONS=-XX:-UseContainerSupport`. Assinatura de desenvolvimento, não chave de publicação. Lista completa de limites em `README.md`.

Nenhum APK foi instalado no aparelho conectado. Nenhuma chave externa foi usada. Sem alegação de escopo comercial completo.

## Artefato verificado

Compilação 1.3.0+7 concluída. Nenhuma instalação automática realizada.

- Arquivo: `build/app/outputs/flutter-apk/app-release.apk`
- Tamanho: `74624519` bytes (74,6 MB decimais).
- SHA-256: `e86fb600fd23ea38f71dbab82138126278959a770a10ceba5eef8d54b5e618ec`
- `apksigner verify --verbose`: assinatura APK v2 válida; assinatura de desenvolvimento mantida.
- Compilação exige tratamento do aviso Java/cgroup descrito no README neste ambiente.
- Avisos não bloqueantes: migração futura de Kotlin no `share_plus` e referência Cupertino de dependência sem fonte empacotada. Interface própria usa ícones Material; auditoria completa dos seletores nativos ainda pendente.

## Correção 1.0.1 — diagnóstico HTTP 429

Erros de cota/créditos agora são distintos de limite temporário de requisições/tokens. Corpos de erro em streaming são lidos com limite de 64 KiB; somente códigos reconhecidos orientam mensagens, sem exibir texto bruto do provedor. Sete testes adicionais cobrem streaming, JSON comum e corpo inválido. Falha real da conta do usuário ainda não diagnosticada: nenhuma credencial foi solicitada ou utilizada.

## Versão 1.1.0 — ChatGPT por assinatura

- Login via navegador oficial, registro dinâmico de cliente, callback loopback, PKCE, state e nonce.
- Validação RS256 contra JWKS oficial, issuer/audience/expiração/identidade e permissões de uso do plano.
- Contas/registrations separadas em armazenamento seguro; host ID estável; renovação serializada e rotação dos tokens.
- Catálogo OAuth, seleção de modelo, teste de geração, associação às tarefas e Responses API sem parâmetros incompatíveis.
- Falhas de elegibilidade, limites, conexão e streams interrompidos não causam fallback para API paga.
- Logout com tentativa de revogação, cancelamento de envios e aviso quando revogação não for confirmada. Exclusão total também tenta revogar antes de apagar cofre.
- 21 testes adicionais de segurança, isolamento entre contas, protocolos e tela. Fluxo de callback usa socket loopback real; endpoints OAuth/inferência são simulados. **Login na OpenAI e inferência usando Plus do usuário ainda não validados.**

## Versão 1.1.1 — legibilidade e autorização persistente

- Usuário confirmou funcionamento do login ChatGPT da versão 1.1.0 no aparelho.
- Corrigido conflito de temas entre `material_ui` e `flutter_markdown`: cores e peso normal explícitos para mensagens do usuário e da IA, sem remover Markdown.
- Consentimento geral persistente para todos os envios solicitados, recursos e provedores; opção marcada no diálogo, salva apenas ao autorizar. Revogação em Privacidade. Contexto continua selecionado pelo usuário.
- Nove testes adicionais verificam contraste mínimo 4,5:1 em ambos os temas/bolhas, estilos Markdown, aceite persistente, envio único, cancelamento, fechamento, outro provedor e revogação.
- Bateria completa: **60 testes aprovados**. `dart analyze --fatal-infos lib test`: nenhum problema encontrado.

## Versão 1.2.0 — estimativas nutricionais por foto/texto

- IA estima peso e kcal/proteínas/carboidratos/gorduras/fibras por 100 g, sem exigir fonte ou valores manuais quando usuário não souber.
- Resultados preenchem editor, não diário. Revisão editável com aviso e hipóteses; salvar continua ação explícita. Refeições com estimativas são identificadas no diário.
- `estimated` e `uncertainty` persistem com ingredientes, favoritas e exportação. Registros antigos continuam compatíveis sem migração. IA não controla campo de origem: aplicativo marca estimativa não verificada.
- Validação de campos e limites recusa nutrientes ausentes, não finitos, negativos e inconsistências básicas. Não valida precisão nutricional real do modelo.
- Sem consulta automática TBCA/TACO ou rótulos; sem mudanças em metas/prescrições clínicas. Inferência real de foto/refeição ainda requer teste do usuário; testes locais usam respostas sintéticas identificadas.
- Bateria completa: **65 testes aprovados**; análise estática sem problemas. Cinco testes adicionais cobrem limites nutricionais, cálculo por porção, origem forçada, persistência/exportação, compatibilidade de registros e edição sem registro automático.

## Versão 1.2.1 — registro sem nome obrigatório

- Causa do erro reportado: `save()` validava nome vazio com `text()`, exibindo mensagem genérica. Nome agora opcional; vazio/espaços usam categoria da refeição. Nomes acima de 120 caracteres recebem erro específico.
- Quatro testes de interface adicionais exercitam gravação real em SQLite de refeição e favorita, com nome vazio/espaços e nome fornecido, preservando estimativas e totais.
- **69 testes aprovados**, análise estática sem problemas. Nenhuma mudança no formato dos dados ou nas credenciais.

## Versão 1.3.0 — agenda e foco dos treinos

- Campos opcionais `days` (1–7), `focus` e `preferences` persistem com rotina; registros anteriores continuam sem dias. Calendário semanal mostra sessões por dia e mantém início manual.
- Geração agora considera nome desejado, dias, foco e preferências; uma rotina por sessão/foco, vários dias repetem sessão. Nenhuma agenda é imposta automaticamente.
- Erro reportado entre 10 e 600 corresponde à validação de descanso. Contrato de IA agora explicita segundos e limites; zero/ausente usa 60 s com aviso de revisão. Outros valores inválidos são recusados com nome do exercício/campo. Cargas iniciais são zeradas localmente, séries/repetições inteiras.
- Mantidos bloqueios clínicos e revisão antes de salvar. Abdômen não é apresentado como perda de gordura localizada.
- Cinco testes adicionais cobrem descanso, carga, schema semanal, persistência/edição, divisão entre dias e bloqueio clínico. Geração real ainda depende de revisão/teste do usuário no aparelho.
- Bateria completa: **74 testes aprovados**; análise estática sem problemas. APK 1.3.0+7 compilado e assinatura v2 verificada.
