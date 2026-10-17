# Arquitetura do QR Ops

## Estrutura

~~~text
lib/
  app/
    qr_ops_app.dart
    qr_ops_bootstrap.dart
    theme/app_theme.dart
  data/
    app_database.dart
    sqlite_qr_record_repository.dart
    indexed_db_qr_record_repository.dart
    qr_record_repository_factory*.dart
  domain/
    qr_record.dart
    qr_record_repository.dart
  features/
    home/
    navigation/
    qr_create/
    qr_history/
    shared/
  main.dart
web/                         Entrypoint, manifest, favicon e ícones Web
android/                     Runner Android
windows/                     Runner Windows
scripts/build_web.sh         Build Web reproduzível no runner Linux
vercel.json                  Build command e saída estática do Vercel
.github/workflows/           Build e deploy ao receber push em main
test/                        Testes de banco, contratos, UI e fluxos
~~~

## Aplicação e navegação

main.dart inicia QrOpsBootstrap. O bootstrap solicita o repositório à fábrica
condicional, apresenta erro recuperável se a abertura falhar e injeta o contrato
QrRecordRepository no app. A interface não abre banco nem executa SQL
diretamente.

QrOpsShell mantém as quatro áreas já existentes. A navegação usa barra
inferior abaixo de 720 px e NavigationRail em larguras maiores. Criar e
consultar histórico são fluxos funcionais; Ler continua como placeholder de
câmera.

QrCreationService valida a entrada, codifica usando a dependência Dart qr e
salva o registro apenas quando a ação explícita de salvar é acionada. A tela
evita iniciar uma segunda gravação enquanto a primeira está em andamento.
QrCodePreview desenha a matriz QR com Flutter Canvas.

## Contrato de dados e persistência

O modelo imutável QrRecord conserva ID UUID, tipo de operação, simbologia,
tipo de conteúdo, conteúdo original e data UTC. QrRecordRepository define
inserção, consulta por ID, listagem recente e exclusão.

A fábrica qr_record_repository_factory.dart escolhe a implementação no tempo
de compilação:

- Android/Windows (dart.library.io): abre o SQLite existente e utiliza
  SqliteQrRecordRepository.
- Web (dart.library.js_interop): utiliza IndexedDbQrRecordRepository com
  idb_shim e o IndexedDB do navegador.
- Outros alvos: a implementação stub informa que a persistência não é
  suportada.

O SQLite continua na versão 2, com a tabela qr_records, índice de data e
migração não destrutiva v1→v2. O repositório Web cria o banco IndexedDB
qr_ops_history, versão 1, com object store qr_records indexado pela chave id.
Os campos são mantidos, incluindo o conteúdo original e a data UTC em
milissegundos. A ordenação e o limite do contrato são aplicados na leitura.
Transações são aguardadas antes de confirmar operações.

O histórico Web persiste em recarregamentos e ao fechar/reabrir o mesmo perfil
do navegador, enquanto seus dados locais forem mantidos. Android, Windows e
Web guardam cópias separadas. Não existe importação/migração entre plataformas,
backup, sincronização ou banco central.

O conteúdo é dado do usuário e permanece sem criptografia adicional; a
aplicação não o escreve em logs. O navegador pode remover dados locais por
limpeza do usuário, modo privado, política de armazenamento ou falta de espaço.

## Web e Vercel

web/index.html, web/manifest.json, favicon e ícones foram gerados pelo scaffold
oficial do Flutter Web. Título e metadados descrevem QR Ops; os ícones continuam
sendo os arquivos genéricos fornecidos pelo scaffold.

O build Flutter Web produz build/web. O workflow do GitHub instala versões
fixadas de Flutter e Vercel CLI, executa vercel build --prod e publica o
artefato usando vercel deploy --prebuilt --prod. O comando de build em
vercel.json chama scripts/build_web.sh; o output directory é build/web.
Assim, Flutter está disponível no runner do GitHub Actions, não se presume que
esteja instalado no builder nativo do Vercel. O cache de Actions guarda SDK e
pacotes entre execuções.

O app não implementa rotas URL profundas: a navegação atual é por estado dentro
da página inicial. Portanto não foi adicionada regra SPA de rewrite. O deploy
automático depende da criação do projeto e de três secrets do GitHub
(VERCEL_TOKEN, VERCEL_ORG_ID, VERCEL_PROJECT_ID); ainda não foi conectado ou
testado em conta externa.

## Limites e segurança

IndexedDB é armazenamento local do navegador, não compartilhado entre usuários
ou dispositivos. Não há autenticação, backend, sincronização, dados empresariais,
licença ou direitos de acesso implementados. Recursos pagos e empresariais
permanecem fora desta etapa; eventual autorização de operações protegidas deve
ser verificada no servidor em uma etapa futura.

## Funcionalidades

Implementado: criar QR localmente, pré-visualizar, salvar, listar e excluir
histórico local em SQLite no Android/Windows e IndexedDB na Web. Não
implementado: leitura por câmera, códigos de barras, OCR, pesquisa, exportação,
login, sincronização, contas/organizações, licenças, QR Ops Admin, anúncios e
pagamentos.