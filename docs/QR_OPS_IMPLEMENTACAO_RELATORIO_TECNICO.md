# QR Ops — relatório técnico de implementação

**Data da revisão:** 24/10/2026  
**Escopo:** implementação local das propostas de Organização, criação em massa, OCR e leitura sequencial em massa.  
**Restrições:** sem alterações no Supabase remoto, sem commit, push, deploy ou publicação.

## Arquitetura inspecionada

- Aplicação Flutter com navegação principal em `lib/features/navigation/qr_ops_shell.dart`.
- Criação individual e codificação QR reutilizadas por `QrCreationService`.
- Persistência local através de `QrRecordRepository`, com implementações SQLite e IndexedDB.
- Histórico e biblioteca em telas próprias de `lib/features/qr_history/`.
- Leitura pela biblioteca `mobile_scanner`; cópia e compartilhamento usam APIs de plataforma existentes.
- Exportação de PNG reaproveita `QrPngExporter`; o lote usa `archive` para ZIP e um gerador PDF interno.
- OCR foi separado por plataforma por meio de `ocr_engine.dart`, `ocr_engine_native.dart`, `ocr_engine_web.dart` e `ocr_engine_stub.dart`.
- A sincronização remota existente usa `SupabaseQrSyncTransport` e a outbox local. Registros OCR são explicitamente locais e não devem entrar na sincronização sem decisão arquitetural própria.

## Decisões técnicas e de privacidade

1. **Criação em massa:** parser limitado inicialmente a 500 itens; aceita linhas, vírgulas, ponto e vírgula, intervalos numéricos e modo de hífen literal. Duplicatas são sinalizadas e preservadas, não removidas silenciosamente.
2. **Exportação:** ZIP contém um PNG por item, com nomes sanitizados e sufixos para nomes repetidos. PDF oferece folha de etiquetas e relatório paginado. Resolução PNG e dimensão impressa são parâmetros distintos.
3. **OCR:** o reconhecimento é iniciado somente por ação explícita. O texto é editável e o salvamento é manual. A imagem original não é persistida como registro OCR. Não há envio de imagens a serviço remoto nesta implementação.
4. **Leitura em massa:** usa captura sequencial, com início explícito, pausa, retomada e finalização. A lista é temporária até o usuário confirmar o salvamento no histórico. A tela não promete detectar vários QR Codes no mesmo quadro.
5. **Integridade de sincronização:** `QrRecordOperation.ocr` é recusada pelo transporte remoto para evitar classificação acidental como leitura/criação sincronizável. O escopo de sincronização bidirecional e isolamento de registros locais entre contas continua sujeito à pendência arquitetural já identificada; não foi alterado nesta tarefa.
6. **Dependências:** são reutilizados `mobile_scanner`, `archive`, `file_saver`, `share_plus` e `flutter_ocr_native` declarados no projeto. Não foi adicionada dependência de OCR remoto ou serviço pago. O PDF é produzido localmente pelo código do projeto, sem novo pacote PDF.

## Matriz de validação

| Área | Teste/validação | Estado |
|---|---|---|
| Parser de lotes | Intervalos, hífen literal, duplicatas, limites e zeros à esquerda | **Passou**: 9 testes |
| Criação em massa | Seleção, revisão e confirmação antes de persistir | **Passou**: teste de widget |
| ZIP/PDF | Cabeçalhos, nomes repetidos e paginação | **Passou**: 3 testes; validação estrutural, não teste de impressão física |
| OCR | Sem reconhecimento automático; edição e salvamento explícito | **Passou**: teste de widget com engine simulada |
| Persistência OCR | Inserção/edição/exclusão local sem outbox de sync | **Passou**: teste SQLite |
| Biblioteca/Organizar | Seleção filtrada e exclusão em lote com confirmação | **Passou**: teste de widget |
| IndexedDB/outbox | Persistência e isolamento por owner; compatibilidade de versão | **Passou**: 10 testes; versão da outbox alinhada a v3 |
| Flutter analyze | Análise completa | **Passou**: `flutter analyze --no-pub`, sem problemas |
| Testes Flutter completos | Regressão geral | **Passou**: 105 aprovados, 2 ignorados; nenhum teste falhou |
| `git diff --check` | Espaçamento/patch | **Passou** sem erros; Git emitiu apenas avisos de conversão LF/CRLF |
| Build Web | Compatibilidade de compilação | **Passou**: `flutter build web --release --no-pub` (87,1 s) |
| Windows/Android reais | Câmera, OCR, compartilhamento e impressão | Pendente; não declarar suporte validado sem execução em dispositivos reais |
| Desempenho | Lotes de 10, 100 e 500 itens | Pendente; não há benchmark concluído |

## Riscos e limitações conhecidas

- O OCR depende de implementação e suporte por plataforma; o stub indica indisponibilidade onde não há engine compatível. A compilação por plataforma e a execução real precisam ser verificadas.
- Câmera, permissões, download e compartilhamento dependem do sistema operacional e não podem ser plenamente comprovados por testes unitários.
- O PDF é gerado por código interno e precisa ser validado por um leitor PDF e por impressão/leitura real dos QR Codes antes de ser considerado pronto para produção.
- O processamento de até 500 códigos pode exigir tempo/memória relevantes; o limite é uma proteção inicial, não um benchmark de desempenho.
- O modelo local atual e a sincronização de contas ainda requerem uma decisão arquitetural para sincronização bidirecional segura. Nenhuma migração remota foi aplicada.
- A leitura em massa usa leitura sequencial; não garante reconhecimento simultâneo de vários códigos no mesmo quadro.

## Estado de entrega por fase

- **Fase 0 — análise técnica:** concluída para a arquitetura e dependências locais inspecionadas; as limitações de sincronização estão documentadas.
- **Fase 1 — Organizar:** implementação e testes automatizados de seleção/exclusão em lote concluídos. Pesquisa continua limitada ao conjunto carregado atualmente pelo repositório; paginação real para dezenas de milhares de itens não foi implementada.
- **Fase 2 — criação em massa:** implementação e testes do parser, prévia, seleção, validação e salvamento explícito concluídos. O tamanho personalizado não faz parte da primeira versão.
- **Fase 3 — ZIP/PDF:** implementação e testes estruturais concluídos. Testes físicos de impressão e leitura dos códigos exportados continuam pendentes.
- **Fase 4 — OCR:** fluxo de imagem, ação explícita, edição e salvamento manual implementados; teste de widget usa engine simulada. Teste real do OCR em Web/Windows/Android ainda pendente.
- **Fase 5 — Organizar OCR:** consulta/edição e ações explícitas foram implementadas; teste de persistência cobre o modelo local. Reprocessamento da imagem original não foi incluído, pois a imagem não é persistida.
- **Fase 6 — leitura em massa:** implementação sequencial com controles explícitos feita. Testes reais de câmera e permissões ainda pendentes.
- **Fase 7 — sincronização:** OCR fica local e é bloqueado no transporte remoto; não houve alteração no Supabase remoto. A sincronização bidirecional e o escopo por proprietário do armazenamento local permanecem pendências arquiteturais.
- **Fase 8 — validação integrada:** análise estática, suite de testes e build Web passaram. Benchmarks 10/100/500 e testes manuais de plataforma permanecem pendentes.

## Estado de entrega

Validação automatizada concluída para o ambiente disponível: `flutter analyze --no-pub` sem problemas; `flutter test --no-pub --reporter compact` com 105 aprovados e 2 ignorados; `flutter build web --release --no-pub` aprovado; `git diff --check` aprovado. Os dois testes ignorados incluem integração que depende de configuração local do Supabase. Não foram executados builds Windows/Android nem testes manuais em dispositivos físicos.

O trabalho permanece apenas local e sem commit/push/deploy conforme solicitado.

## Atualizacao corretiva - 2026-10-24

- O parser de criacao em massa agora expande intervalos com prefixo alfanumerico compartilhado: `A1-A10` gera `A1` ate `A10`; `ITEM008-ITEM010` preserva os zeros a esquerda. Intervalos numericos, hifen literal e limites continuam cobertos por testes.
- A tela OCR agora oferece selecao de arquivo de imagem ou PDF. Na Web, PDFs com texto selecionavel usam extracao de texto; paginas digitalizadas passam por renderizacao e OCR no navegador. O processamento e iniciado somente pelo botao `Scanear`, aceita ate 30 paginas por PDF e nao persiste o arquivo de origem.
- As bibliotecas PDF.js e Tesseract.js sao carregadas sob demanda de CDN publico na Web. O conteudo do arquivo e processado no navegador; o arquivo PDF/imagem nao e enviado a esses CDNs. A leitura de PDF ainda nao esta implementada no alvo nativo.
- Validacao apos a correcao: `flutter analyze --no-pub` sem problemas; suite completa `flutter test --no-pub --reporter compact` com 107 aprovados e 2 ignorados; `flutter build web --release --no-pub` aprovado; `node --check web/qr_ops_ocr.js` e `git diff --check` aprovados.
- O servidor local `http://localhost:8080` responde HTTP 200 e serve o build atualizado. A leitura real de PDFs e OCR ainda requer verificacao manual no navegador com arquivos de teste representativos.

## Atualizacao de Ler - extracao de QR Codes de PDF - 2026-10-24

- A tela `Ler código` mantém os controles existentes e adiciona resultados de PDF abaixo do resultado principal: cada ocorrência encontrada é listada com número, página e conteúdo decodificado, com opção de copiar o conteúdo individual.
- A extração percorre as páginas do PDF (limite de 30 páginas e 20 MB), tenta detectar múltiplos QR Codes por página via `BarcodeDetector` quando o navegador oferece suporte e usa `jsQR` como fallback. O fallback pode detectar apenas um QR Code por página.
- O botão `Baixar resultados em TXT` exporta o nome do PDF, total de códigos, página de cada ocorrência e conteúdo integral do código. O arquivo de origem permanece em memória e não é persistido.
- Validacao da alteracao: `flutter analyze --no-pub` sem problemas; `flutter test --no-pub --reporter compact` com 107 aprovados e 2 ignorados; build Web de release e `node --check web/qr_ops_ocr.js` em execucao/validacao final. O teste manual com PDFs contendo um e varios QR Codes ainda precisa ser feito no navegador.


## Atualização — upload de PDF na área Ler (2026-10-24)

- A área **Ler** agora apresenta ações separadas e próximas: **Ler de uma imagem** e **Ler de um PDF**. Os controles ficam abaixo da área de câmera, agrupados em `Wrap` para reorganizar automaticamente em telas estreitas; a ação PDF é exibida na Web.
- O PDF é processado sob ação explícita do usuário, usando PDF.js para renderizar as páginas e `BarcodeDetector` quando suportado, com `jsQR` como fallback. A leitura percorre até 30 páginas e coleta códigos QR por página; o resultado principal permanece selecionável no cartão de leitura, e a lista extraída pode ser exportada em TXT.
- Limites: arquivo até 20 MB; PDFs protegidos por senha ou páginas com QR ilegível podem falhar. O processamento ocorre no navegador; PDF.js e jsQR são carregados sob demanda de CDN público. O arquivo não é persistido pelo QR Ops.
- A leitura de QR em PDF está disponível apenas na versão Web nesta etapa; a leitura de imagem existente permanece separada e inalterada.
- Validação: `flutter analyze --no-pub` sem problemas; `node --check web/qr_ops_ocr.js` e `git diff --check` aprovados; `flutter build web --release --no-pub` aprovado. A suíte completa foi iniciada, mas teve uma falha em `qr_library_bulk_actions_test.dart` (esperava biblioteca vazia, encontrou um registro) e ficou parada no teste final de `widget_test.dart`; a suíte não foi considerada aprovada nesta execução. O teste de PDF real no navegador ainda precisa de validação manual.
