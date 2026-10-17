# Changelog

## Não lançado — Etapa 3: suporte Web e preparação para Vercel (2026-10-16)

- Criado o runner web/ com scaffold Flutter, manifest, favicon e ícones; título
  e metadados passaram a identificar QR Ops.
- Adicionada persistência IndexedDB (idb_shim) que mantém o contrato
  QrRecordRepository, preserva os campos do histórico, ordena, consulta e
  exclui registros locais.
- Seleção condicional usa SQLite no Android/Windows e IndexedDB na Web; o
  bootstrap deixou de importar SQLite incondicionalmente.
- Acrescentados testes de contrato IndexedDB, inicialização Web e widgets para
  layout estreito/largo e falhas de leitura, mantendo os testes SQLite
  existentes.
- Preparados vercel.json, scripts/build_web.sh e workflow GitHub Actions para
  build Flutter no runner GitHub e publicação pré-compilada no Vercel.
- Adicionado .vercel/ ao .gitignore para manter arquivos locais de vínculo e
  ambiente do CLI fora do repositório.
- Smoke test em Chrome confirmou inicialização, prévia/geração, histórico,
  IndexedDB após recarregar/fechar/reabrir o navegador e exclusão.
- flutter analyze --no-pub passou, 23 testes passaram e 1 foi ignorado no host
  Windows; builds Web debug e release foram concluídos.
- Builds Android e Windows foram bloqueados, respectivamente, pela ausência do
  Android SDK e da toolchain Visual Studio C++.
- GitHub/Vercel externo não configurados; nenhum deploy foi realizado.
- Login, backend, sincronização, câmera, OCR, recursos empresariais, anúncios
  e pagamentos continuam fora do escopo.

## Diagnóstico e validação da Etapa 2.1 (2026-10-16)

- Reexecutados flutter analyze --no-pub e flutter test --no-pub: análise sem
  problemas e 14 testes aprovados.
- Acrescentados testes para índice de ordenação do histórico e recuperação de
  registro depois de fechar/reabrir SQLite baseado em arquivo com FFI.
- Confirmada por testes a criação da matriz QR, preservação do conteúdo
  original, validação de conteúdo vazio/longo e salvamento local. Decodificação
  independente não foi validada.
- flutter doctor -v confirmou ausência do Android SDK e do Visual Studio com
  workload C++; builds Android e Windows continuam sem validação.
- O build Web não teve sucesso na Etapa 2.1 porque ainda não existia web/.

## Não lançado — Persistência e criação de QR Code (2026-10-16)

- Atualizado o SQLite para esquema v2 com tabela qr_records e migração testada
  a partir da versão 1 preservando dados existentes.
- Adicionados modelo imutável, contrato de repositório e implementação SQLite
  para inserir, consultar e excluir registros locais.
- Adicionados UUID v4 locais; isso não implementa sincronização.
- Implementadas validação, prévia, criação de QR Codes e salvamento explícito
  no histórico local.
- A área Organizar passou a mostrar o histórico e permitir exclusão confirmada.
- Adicionadas as dependências qr e uuid; nenhuma dependência de câmera foi
  adicionada.

## 1.0.0 — Fundação inicial (2026-10-16)

- Criado projeto Android Flutter qr_ops e runner Flutter para Windows desktop.
- Adicionado tema Material 3, locale pt-BR e navegação adaptável.
- Adicionada inicialização SQLite versionada com migração identificadora e
  estado de falha recuperável.
- Adicionados testes de persistência, navegação e falha de inicialização.
