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
web/                         Entrypoint, manifest, favicon e ├¡cones Web
android/                     Runner Android
windows/                     Runner Windows
scripts/build_web.sh         Build Web reproduz├¡vel no runner Linux
vercel.json                  Build command e sa├¡da est├ítica do Vercel
.github/workflows/           Build e deploy ao receber push em main
test/                        Testes de banco, contratos, UI e fluxos
~~~

## Aplica├º├úo e navega├º├úo

main.dart inicia QrOpsBootstrap. O bootstrap solicita o reposit├│rio ├á f├íbrica
condicional, apresenta erro recuper├ível se a abertura falhar e injeta o contrato
QrRecordRepository no app. A interface n├úo abre banco nem executa SQL
diretamente.

QrOpsShell mant├®m as quatro ├íreas j├í existentes. A navega├º├úo usa barra
inferior abaixo de 720 px e NavigationRail em larguras maiores. Criar e
consultar hist├│rico s├úo fluxos funcionais; Ler continua como placeholder de
c├ómera.

QrCreationService valida a entrada, codifica usando a depend├¬ncia Dart qr e
salva o registro apenas quando a a├º├úo expl├¡cita de salvar ├® acionada. A tela
evita iniciar uma segunda grava├º├úo enquanto a primeira est├í em andamento.
QrCodePreview desenha a matriz QR com Flutter Canvas.

A cria├º├úo suporta texto livre, URL HTTP(S), telefone, e-mail, SMS e Wi-Fi.
QrCreationService comp├Áe os payloads padronizados e valida os campos antes da
codifica├º├úo. O campo existente content_type identifica o tipo em registros
novos; registros antigos continuam com o valor text e n├úo exigem migra├º├úo. Os
ajustes de apar├¬ncia s├úo locais ├á pr├®via e usam uma paleta de alto contraste.
N├úo h├í logotipo, exporta├º├úo ou compartilhamento implementados.

## Contrato de dados e persist├¬ncia

O modelo imut├ível QrRecord conserva ID UUID, tipo de opera├º├úo, simbologia,
tipo de conte├║do, conte├║do original e data UTC. QrRecordRepository define
inser├º├úo, consulta por ID, listagem recente e exclus├úo.

A f├íbrica qr_record_repository_factory.dart escolhe a implementa├º├úo no tempo
de compila├º├úo:

- Android/Windows (dart.library.io): abre o SQLite existente e utiliza
  SqliteQrRecordRepository.
- Web (dart.library.js_interop): utiliza IndexedDbQrRecordRepository com
  idb_shim e o IndexedDB do navegador.
- Outros alvos: a implementa├º├úo stub informa que a persist├¬ncia n├úo ├®
  suportada.

O SQLite continua na vers├úo 2, com a tabela qr_records, ├¡ndice de data e
migra├º├úo n├úo destrutiva v1ÔåÆv2. O reposit├│rio Web cria o banco IndexedDB
qr_ops_history, vers├úo 1, com object store qr_records indexado pela chave id.
Os campos s├úo mantidos, incluindo o conte├║do original e a data UTC em
milissegundos. A ordena├º├úo e o limite do contrato s├úo aplicados na leitura.
Transa├º├Áes s├úo aguardadas antes de confirmar opera├º├Áes.

O hist├│rico Web persiste em recarregamentos e ao fechar/reabrir o mesmo perfil
do navegador, enquanto seus dados locais forem mantidos. Android, Windows e
Web guardam c├│pias separadas. N├úo existe importa├º├úo/migra├º├úo entre plataformas,
backup, sincroniza├º├úo ou banco central.

O conte├║do ├® dado do usu├írio e permanece sem criptografia adicional; a
aplica├º├úo n├úo o escreve em logs. O navegador pode remover dados locais por
limpeza do usu├írio, modo privado, pol├¡tica de armazenamento ou falta de espa├ºo.

## Web e Vercel

web/index.html, web/manifest.json, favicon e ├¡cones foram gerados pelo scaffold
oficial do Flutter Web. T├¡tulo e metadados descrevem QR Ops; os ├¡cones continuam
sendo os arquivos gen├®ricos fornecidos pelo scaffold.

O build Flutter Web produz build/web. O workflow do GitHub instala vers├Áes
fixadas de Flutter e Vercel CLI, executa vercel build --prod e publica o
artefato usando vercel deploy --prebuilt --prod. O comando de build em
vercel.json chama scripts/build_web.sh; o output directory ├® build/web.
Assim, Flutter est├í dispon├¡vel no runner do GitHub Actions, n├úo se presume que
esteja instalado no builder nativo do Vercel. O cache de Actions guarda SDK e
pacotes entre execu├º├Áes.

O app n├úo implementa rotas URL profundas: a navega├º├úo atual ├® por estado dentro
da p├ígina inicial. Portanto n├úo foi adicionada regra SPA de rewrite. O deploy
autom├ítico depende da cria├º├úo do projeto e de tr├¬s secrets do GitHub
(VERCEL_TOKEN, VERCEL_ORG_ID, VERCEL_PROJECT_ID); ainda n├úo foi conectado ou
testado em conta externa.

## Limites e seguran├ºa

IndexedDB ├® armazenamento local do navegador, n├úo compartilhado entre usu├írios
ou dispositivos. N├úo h├í autentica├º├úo, backend, sincroniza├º├úo, dados empresariais,
licen├ºa ou direitos de acesso implementados. Recursos pagos e empresariais
permanecem fora desta etapa; eventual autoriza├º├úo de opera├º├Áes protegidas deve
ser verificada no servidor em uma etapa futura.

## Pontos de extens├úo futuros

- Categorias e identificadores operacionais (por exemplo, gaiola ou palete)
  podem ser associados como metadados a um registro de cria├º├úo. Ainda n├úo h├í
  entidade ou contrato de dados para esses conceitos; o conte├║do QR gen├®rico
  continua independente.
- Limites e capacidades comerciais devem ser definidos em um servi├ºo de
  produto/conta separado da cria├º├úo e da interface. N├úo existe plano ativo,
  autentica├º├úo comercial ou bloqueio de recursos.
- Exporta├º├úo pode reutilizar a matriz j├í gerada, mas requer decidir os formatos
  e as APIs multiplataforma de compartilhamento antes de implementar.
- QR din├ómico requer servi├ºo de redirecionamento hospedado, persist├¬ncia,
  seguran├ºa, disponibilidade e custo operacional; os c├│digos atuais s├úo
  est├íticos e incluem diretamente o conte├║do.

## Funcionalidades

Implementado: criar QR localmente, pr├®-visualizar, salvar, listar e excluir
hist├│rico local em SQLite no Android/Windows e IndexedDB na Web. N├úo
implementado: leitura por c├ómera, c├│digos de barras, OCR, pesquisa, exporta├º├úo,
login, sincroniza├º├úo, contas/organiza├º├Áes, licen├ºas, QR Ops Admin, an├║ncios e
pagamentos.

## Arquitetura alvo permanente: Supabase + PostgreSQL

- Cliente: Flutter.
- Backend e autenticação: Supabase Auth.
- Banco central: PostgreSQL gerenciado pelo Supabase.
- Persistência local mantida: SQLite em Android/Windows e IndexedDB na Web.
- O contrato de domínio `QrRecordRepository` permanece independente da UI e do provedor de armazenamento.
- Segurança de dados central: Row Level Security (RLS) no PostgreSQL; nunca incluir chave `service_role` no aplicativo.
- URL do projeto e chave pública devem ser fornecidas por configuração de build/ambiente, sem segredos no repositório.
- Histórico global para usuários autenticados, com `author_id`; registros imutáveis e exclusão restrita ao autor até que exista uma política administrativa formal.

### Persistência local e remota

SQLite e IndexedDB permanecem como armazenamento local/cache. A sincronização será explícita e idempotente, usando UUID estável, estado de sincronização e política de conflito. Uma gravação local não deve ser apresentada como sincronizada até confirmação do servidor. A estratégia offline deverá distinguir registros pendentes dos registros confirmados remotamente.

### Login por QR pessoal

O número impresso no QR é identificador, não credencial. O fluxo não pode autenticar somente com um número previsível, como `251`; deve exigir confirmação adicional de identidade. Tokens de sessão ficam sob responsabilidade do Supabase Auth. Desafios de uso único, expiração e limitação de tentativas devem ser validados no servidor.

### Esquema remoto inicial

A migração `supabase/migrations/202610220001_create_shared_qr_records.sql` cria `public.qr_records` e políticas RLS. Usuários autenticados podem consultar o histórico global e inserir registros apenas em seu próprio nome. Não há política de UPDATE. A exclusão é restrita ao autor. Política administrativa só deve ser adicionada quando houver papéis e auditoria definidos.

### Configuração e tarefas externas

A dependência `supabase_flutter` foi adicionada como preparação. Ainda será necessário criar o projeto Supabase, aplicar a migração, configurar URL/chave pública por ambiente, implementar o repositório remoto, autenticação e sincronização e testar RLS com usuários diferentes. Chaves públicas não substituem RLS; a chave `service_role` nunca deve ser distribuída ao Flutter.

### Validação de segurança obrigatória

Testar que usuário anônimo não lê nem grava; usuário autenticado lê o histórico global; não é possível inserir com autoria alheia, excluir registros de terceiros ou atualizar registros; e falhas de rede não são apresentadas como gravações sincronizadas.
