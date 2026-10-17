# Estado do projeto

Atualizado em 2026-10-16.

## Estado implementado

- Flutter 3.47.5 / Dart 3.13.4; app em pt-BR, Material 3 e navegação adaptável.
- Criação local de QR Codes com validação, prévia, salvamento explícito e
  histórico com consulta e exclusão.
- SQLite v2 preservado no Android e Windows.
- Fábrica de repositório seleciona IndexedDB na Web e mantém o contrato
  QrRecordRepository.
- Runner Web oficial do Flutter criado com web/index.html, manifest, favicon e
  ícones. Metadados identificam QR Ops; imagens seguem o scaffold genérico.
- Build/deploy Vercel preparado em vercel.json, scripts/build_web.sh e workflow
  GitHub Actions, com Flutter e Vercel CLI versionados e deploy pré-compilado.

## Verificações da Etapa 3

| Comando/verificação | Resultado observado |
| --- | --- |
| flutter --version | Flutter 3.47.5 stable / Dart 3.13.4 |
| flutter doctor -v | Chrome/Edge disponíveis; Android SDK e Visual Studio com workload C++ ausentes |
| flutter devices | Windows, Chrome e Edge; nenhum Android detectado |
| flutter pub get | Sucesso; idb_shim 2.10.1+1 adicionado e lockfile atualizado |
| flutter pub get --enforce-lockfile | Sucesso; dependências resolvidas sem alterar o lockfile |
| flutter analyze --no-pub | Sucesso; sem problemas |
| flutter test --no-pub | Sucesso; 23 passaram e 1 foi ignorado no host Windows |
| flutter test --no-pub test/indexed_db_qr_record_repository_test.dart | Sucesso; 7 casos passaram no VM com factory em memória |
| flutter test --no-pub --platform chrome ... | Não concluiu; o runner permaneceu em loading e foi encerrado, sem resultado válido |
| flutter build web --debug --no-pub | Sucesso; gerou build/web |
| flutter build web --release --no-pub | Sucesso; gerou build/web. Aviso de fonte CupertinoIcons ausente; não há uso de CupertinoIcons no código |
| Chrome headless, smoke test do build de depuração | Inicialização, geração/prévia, salvamento, consulta do histórico, IndexedDB após recarga e exclusão verificados |
| Chrome headless, perfil persistente temporário | Registro encontrado no IndexedDB antes e após fechar/reabrir o navegador |
| Chrome headless, smoke test de build de produção | Título QR Ops, prévia e gravação verificadas; sem erros de console |
| Viewport 390×844 no Chrome | Histórico renderizado com navegação inferior e conteúdo adaptado à largura |
| flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8765 --no-pub | Serviu o app para os smoke tests; processo encerrado após a validação |
| flutter build apk --debug --no-pub | Bloqueado: No Android SDK found |
| flutter build windows --debug --no-pub | Bloqueado: Unable to find suitable Visual Studio toolchain |
| vercel.json via ConvertFrom-Json do PowerShell | JSON válido; buildCommand aponta para scripts/build_web.sh e saída build/web |

O Flutter Web foi compilado em depuração e produção e executado localmente em
Chrome. O teste automatizado Flutter direcionado ao Chrome não produziu
resultado e permanece como limitação distinta do smoke test real.

## Persistência e plataformas

| Plataforma | Implementação | Estado |
| --- | --- | --- |
| Android | SQLite com sqflite | Código e testes existentes preservados; build bloqueado pela ausência do Android SDK |
| Windows | SQLite com sqflite_common_ffi | Código e testes existentes preservados; build bloqueado pela ausência da toolchain Visual Studio C++ |
| Web | IndexedDB com idb_shim 2.10.1+1 | Builds debug/release e operações locais verificadas em Chrome |

Os dados ficam separados em cada dispositivo/perfil. Não há migração ou
sincronização entre plataformas.

## Ausente ou planejado

- Scanner por câmera, códigos de barras, OCR, pesquisa, favoritos e exportação.
- Login, API, banco central, sincronização, usuários, organizações e permissões.
- Licenças/planos, QR Ops Admin, publicidade e pagamentos.
- Identificador Android com.example.qr_ops provisório.
- Decodificação independente do QR em teste permanece pendente.

## Publicação no Vercel

O workflow .github/workflows/vercel-deploy.yml dispara em push ao branch main.
Usa GitHub Actions para instalar Flutter e Vercel CLI e publica build
pré-compilado via Vercel CLI. É necessário criar/configurar o projeto Vercel e
cadastrar VERCEL_TOKEN, VERCEL_ORG_ID e VERCEL_PROJECT_ID nos secrets do GitHub.
Projeto externo, secrets, vínculo do repositório e deploy ainda não foram
configurados nem testados.

O fluxo não usa a compilação Git nativa do Vercel. Se o projeto também ficar
ligado ao build Git nativo, deve-se desativar essa compilação para que a
workflow do GitHub seja a única responsável pelo build e deploy. O teste do
comando Vercel CLI só poderá ocorrer depois da configuração externa.

## Limitações

- A action habilita cache do Flutter SDK e do pub para reduzir downloads nas
  execuções seguintes. A primeira execução de CI pode levar mais tempo.
- No navegador, limpeza de dados, modo privado e políticas do site podem apagar
  ou limitar o histórico.
- A suíte Flutter em Chrome travou neste ambiente sem produzir resultado; a
  validação do navegador foi feita manualmente com smoke tests no Chrome.
- A publicação automática só será comprovada após cadastrar os secrets e
  observar um deploy real.
- O Flutter não está no PATH do ambiente Windows auditado; os comandos desta
  etapa usaram o SDK em C:\Users\missp\develop\flutter. A configuração global
  não foi alterada.
- Todos os arquivos do projeto aparecem como não rastreados no Git; não havia
  baseline versionado para comparar. Nenhuma alteração foi revertida ou
  descartada.

## Histórico

As Etapas 2 e 2.1 verificaram a criação do QR, o contrato do repositório e a
migração SQLite v1→v2. Consulte CHANGELOG.md para os registros anteriores.
