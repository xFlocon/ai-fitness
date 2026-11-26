# Catálogo offline de exercícios

1.388 registros: 1.324 do Flow, 57 do Workout Free Videos, seis do Wikimedia Commons e um do wger. Há mídia local em **66 registros**: 57 MP4, oito GIFs e um par de ilustrações. Vídeos e GIFs locais também têm miniaturas estáticas. Alguns registros de fontes diferentes descrevem o mesmo movimento. Busca consulta nomes em português e inglês, equipamento e glossário de sinônimos, sem trocar o ID da variante. Cobertura de mídia não é cobertura integral do catálogo.

Todos os **1.257 GIFs disponíveis do Flow** ficam [online](https://github.com/xFlocon/ai-fitness/tree/catalog-media-v2), incluindo cinco com versão offline. O app aceita 26 GIFs do Flow com revisão visual: 24 do lote publicado e dois revisados na versão 1.6.4. Os demais têm aviso e não substituem uma demonstração aceita para salvar sugestão. Sem busca do YouTube configurada, a IA só recebe candidatos com demonstração aceita. O primeiro acesso usa GitHub; o app valida o SHA-256 e guarda o GIF no cache do Android. Só o manifesto acompanha o APK. Gere o catálogo online com `python3 scripts/export_online_gifs.py CAMINHO_FLOW PASTA_SAIDA`, publique créditos e arquivos, e atualize manifesto e revisão no app. A hospedagem não tem garantia de tráfego ilimitado.

## Fontes e licenças

- [Workout Free Videos v2.0.0](https://github.com/namnq/workout-free-videos/tree/f7d829895c02c82d7b56d113fb6955c6ea54c642): CC0. MP4 originais, miniaturas extraídas e nomes traduzidos. Não implica revisão profissional de execução.
- [Flow Exercise Dataset](https://github.com/ozansozuozgit/flow-exercise-dataset/tree/961bb2739015da373daa43b960c28ee839fe93e6): dados MIT. Cinco ilustrações com movimento conferido visualmente, convertidas para GIF e PNG; ajustados fundo, intervalo de quadros e margem do dead bug. Arte declarada CC0 pelo projeto; [aviso do projeto](../assets/exercises/FLOW-NOTICE.md) descreve limites de procedência e precisão. Os demais 1.319 registros são apenas textuais. Validar movimento, variante e procedência antes de liberar mais arte.
- Wikimedia Commons: Wensceslao, CC BY-SA 4.0. [Agachamento livre](https://commons.wikimedia.org/wiki/File:Squats.gif), [burpee](https://commons.wikimedia.org/wiki/File:Burpees.gif) e [joelhos altos com salto](https://commons.wikimedia.org/wiki/File:High_knees.gif). GIFs inalterados; miniaturas recortadas no tempo e redimensionadas, sob mesma licença. Vídeos de supino e outros sob contestação de licença não foram incluídos.
- wger: Everkinetic, CC BY-SA 3.0. Imagens originais de [posição 1](https://wger.de/api/v2/exerciseimage/27/) e [posição 2](https://wger.de/api/v2/exerciseimage/28/) da rosca direta com barra. Uso não exige instalar servidor wger.
- [Três GIFs online do Wikimedia Commons](COMMONS-ONLINE.md): flexão de braços, elevação de pernas deitada e polichinelo alternado frente e trás. Arquivos e créditos publicados na branch `catalog-commons-v1`.
- Hasan/GymVisual: os dados MIT já são base do Flow. A licença do repositório não concede permissão para integrar a mídia GymVisual. ExerciseDB.io: compra e licença próprias necessárias; não permite publicar arquivos brutos como biblioteca pública. Código do AI Fitness continua MIT; mídia mantém licenças acima.

## Atualização fora do app

Clone as revisões acima. Baixe os três GIFs originais do Commons com os nomes `Squats.gif`, `Burpees.gif` e `High_knees.gif`. Baixe os dois PNGs apontados pelo wger, com os nomes `27.png` e `28.png`. Use Python 3, `ffmpeg` e `rsvg-convert`:

```sh
python3 scripts/import_exercise_catalog.py CAMINHO_CLIPS CAMINHO_FLOW CAMINHO_COMMONS CAMINHO_WGER
```

Nenhum servidor adicional é necessário. Ao gerar treino, o app envia até 24 registros resumidos ao provedor de IA após consentimento; não envia arquivos de mídia. A busca opcional no YouTube atende apenas os exercícios sem demonstração local. Modelos remotos ainda precisam de internet e podem consumir cota do próprio provedor.
