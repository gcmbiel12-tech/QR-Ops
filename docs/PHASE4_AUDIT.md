# QR Ops - Fase 4: banco Supabase, autenticacao e sincronizacao

Atualizado em 2026-10-23. Estado de desenvolvimento local. Nenhuma conexao, migracao ou alteracao foi executada no Supabase remoto.

## Modelo de dados atual

A tabela `public.qr_records` representa a entidade `QrRecord` que ja existe no dominio Flutter. `operation_type` discrimina `create` (biblioteca) de `read` (historico). Esta escolha preserva os IDs estaveis e a interface comum dos repositorios locais; as operacoes de retencao sempre filtram `operation_type = 'read'`. A biblioteca e o historico continuam sendo areas distintas da UI. Se a sincronizacao futura exigir ciclos de vida, retencao ou permissao independentes no servidor, uma migracao futura pode separar as tabelas, com migracao de dados explicita; nao foi criada duplicacao prematura nesta fase.

Colunas existentes e novas:

- `id uuid primary key`: UUID estavel gerado no cliente.
- `author_id uuid not null references auth.users(id) on delete restrict`: proprietario remoto; definido pelo repositorio a partir da sessao e validado pela RLS.
- `operation_type text`: `create` ou `read`, com CHECK.
- `symbology`, `content_type`, `content`: tipo e payload, com restricoes de comprimento no esquema original.
- `name`, `description`: metadados opcionais com default vazio.
- `created_at timestamptz`: instante de criacao em UTC.
- `updated_at timestamptz not null default now()`: ultima alteracao no servidor.
- `revision bigint not null default 1 check (revision > 0)`: versao monotonicamente incrementada pelo trigger de UPDATE.

Indices: `qr_records_created_at_idx` para ordenacao global por data/id; `qr_records_author_created_at_idx` para consultas por proprietario/data; `qr_records_author_updated_at_idx` para futura leitura incremental de alteracoes por proprietario. A FK usa `ON DELETE RESTRICT` para nao apagar historico silenciosamente quando uma conta for removida.

A tabela continua unificada por compatibilidade com o modelo e repositorio existentes. Nao ha tabela de sync/outbox, tombstone nem chave de idempotencia persistente ainda; `revision` e somente preparacao para concorrencia futura, nao significa que sincronizacao esteja implementada.

## Migracoes versionadas

1. `202610220001_create_shared_qr_records.sql` - esquema original. Inclui uma politica antiga de SELECT global (`USING (true)`), que e insegura se aplicada.
2. `202610230001_restrict_qr_record_history_to_owner.sql` - habilita e forca RLS; remove todas as politicas existentes da tabela antes de recria-las; cria SELECT/INSERT/UPDATE/DELETE limitadas a `auth.uid()`; valida `author_id` em INSERT e UPDATE; remove grants a PUBLIC/anon/authenticated e concede CRUD a authenticated.
3. `202610230002_add_qr_record_metadata.sql` - adiciona `name` e `description` sem reescrever os registros existentes.
4. `202610230003_add_remote_record_revision.sql` - adiciona `updated_at` e `revision`, indice incremental e trigger que atualiza a data e incrementa a revisao sem alterar `created_at`.

A migracao 001 de seguranca remove todas as policies existentes em `public.qr_records` porque policies permissivas sao combinadas por OR. Isso protege contra policies antigas desconhecidas nessa tabela, mas nao audita automaticamente grants/policies de outras tabelas que possam ser criadas no futuro. Cada nova tabela privada precisa de migracao e teste de RLS proprio.

Antes de aplicar, confirme o historico real do ambiente. Se a migracao original ja tiver sido aplicada, aplique as migracoes corretivas em sequencia em um projeto de desenvolvimento primeiro. Nunca presuma que os arquivos locais descrevem o estado remoto.

## RLS e privilegios esperados

Tabela `public.qr_records`:

- SELECT: `authenticated`, apenas quando `author_id = auth.uid()`.
- INSERT: `authenticated`, somente se `author_id = auth.uid()`.
- UPDATE: `authenticated`, apenas se o registro existente pertence ao usuario e o novo `author_id` continua sendo o mesmo usuario.
- DELETE: `authenticated`, somente para registros do proprio usuario.
- `anon` e `PUBLIC`: sem privilegios de tabela.
- `authenticated`: SELECT, INSERT, UPDATE, DELETE; a RLS restringe cada operacao ao proprietario.
- RLS habilitada e FORCE RLS ativado.

A migracao nao foi aplicada em nenhum banco remoto nesta execucao. O estado de producao e de qualquer projeto de desenvolvimento externo permanece desconhecido.

## Testes SQL

`supabase/tests/qr_records_rls.test.sql` usa pgTAP e contem 22 verificacoes planejadas: RLS habilitada/forcada, colunas de sincronizacao, trigger de revisao, exatamente quatro policies, grants, isolamento A/B, tentativa de leitura/alteracao/exclusao cruzada, insercao propria, falsificacao de `author_id`, transferencia de propriedade, incremento de revisao e bloqueio do usuario anonimo.

O teste ainda NAO foi executado. Nesta maquina nao foram encontrados Supabase CLI, `psql` nem Docker; `supabase/config.toml` tambem nao existe e nao ha nomes de variaveis de ambiente Supabase configurados. Nao foi possivel identificar um projeto remoto de desenvolvimento com seguranca. Para validacao local, instale Docker e Supabase CLI, execute `supabase init` (se ainda nao houver config), revise o arquivo gerado, depois use uma stack descartavel com `supabase start`, `supabase db reset` e `supabase test db`. `supabase db reset` recria o banco local da stack; nunca execute contra producao. A seguranca real do banco nao pode ser declarada comprovada antes disso.

## Integracao Flutter

- `SupabaseAppConfig` usa `--dart-define` para `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY`; rejeita URL sem HTTPS e chaves privilegiadas conhecidas. Nunca inclua `service_role` ou `sb_secret_` no cliente.
- `QrOpsBootstrap` inicializa Supabase opcionalmente depois de abrir o repositorio local. Falha de configuracao ou inicializacao de autenticacao nao bloqueia a persistencia local.
- `SupabaseQrAuthGateway` conecta cadastro, login, logout, recuperacao de senha e eventos de sessao a `supabase_flutter`.
- `SupabaseQrRecordRepository` implementa insercao, listagem, busca por ID, atualizacao, exclusao e limpeza de historico. Todas as operacoes exigem sessao; consultas, atualizacoes e exclusoes tambem incluem filtro por `author_id`, como defesa em profundidade. A RLS continua obrigatoria.
- O mapeamento remoto preserva IDs, metadados e timestamps UTC. A atualizacao nao altera `created_at`.
- Testes unitarios em `test/data/supabase_qr_record_repository_test.dart` validam mapeamento, timestamps, compatibilidade com metadados ausentes, operacao desconhecida e falha sem sessao. Sao testes com cliente Supabase local/falso, nao testes de rede ou de banco real.

Exemplo de configuracao Web (use valores locais e nunca cole credenciais no chat):

```powershell
flutter run -d chrome --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICA
```

Configure no painel a Site URL, templates de e-mail e URLs de redirecionamento para recuperacao de senha. O fluxo real ainda depende de configuracao e testes por plataforma.

## Preservacao local-first

SQLite e IndexedDB continuam sendo os armazenamentos ativos da biblioteca/historico. Login nao envia nem associa automaticamente registros locais a conta. Nenhum fluxo de sync remoto foi conectado a UI. Os dados preexistentes continuam no dispositivo; em dispositivos compartilhados ainda nao existe particionamento local por conta. Antes de sincronizar, implemente consentimento/importacao selecionavel e uma outbox persistente com owner por item, operacao, tombstone, chave idempotente e estado de retry.

## O que falta para sincronizacao real

- Outbox duravel SQLite e IndexedDB.
- Transporte Supabase integrado ao `QrSyncCoordinator`.
- Idempotencia remota e tratamento de conflitos persistente.
- Tombstones para exclusoes sincronizadas.
- Cache/estado remoto particionado por conta e limpeza na troca de usuario.
- Testes reais online/offline, repeticao, retomada e troca de conta.

Os contratos de sincronizacao existentes sao apenas uma abstracao testada; nao os descreva como sync funcional.

## Plataformas

O repositorio configura targets Web, Android e Windows. O build Web pode ser validado neste ambiente. Android requer Android SDK; Windows requer Visual Studio Build Tools. iOS/macOS/Linux nao sao declarados suportados com base no estado observado do repositorio.

## Sequencia segura

1. Instalar/configurar Docker e Supabase CLI; executar a stack local descartavel.
2. Aplicar as migracoes em ordem e executar `supabase test db`.
3. Verificar no painel o estado real de policies, grants e historico de migracoes no projeto alvo.
4. Configurar credenciais publicas locais e testar auth real e recuperacao por plataforma.
5. Implementar outbox persistente, consentimento/importacao e transporte remoto idempotente.
6. Validar A/B, anonimo, `author_id` falsificado, offline/retomada, exclusao, logout e troca de conta.
7. So entao habilitar sincronizacao.

## Validacao local desta rodada

- `dart format` nos arquivos Dart alterados nesta rodada: executado.
- `flutter analyze --no-pub`: sem problemas.
- `flutter test --no-pub`: 84 aprovados e 1 ignorado.
- `flutter build web --release --no-pub`: concluido; avisos nao bloqueantes de ensaio WebAssembly e fonte Cupertino.
- `git diff --check`: aprovado. Os avisos LF/CRLF sao avisos de autocrlf, nao erros de whitespace.
- Teste SQL RLS: nao executado por ausencia de Supabase CLI, `psql`, Docker e config local.

Nenhuma migracao remota, alteracao de dados reais, commit, push ou deploy foi realizada.
