# QR Ops

Aplicativo Flutter em português para criar QR Codes e organizar um histórico
local. A versão Web inicial funciona em navegadores de computadores e celulares.

## Estado atual

- Criação local de QR Codes a partir de texto ou endereço, com validação e
  prévia antes do salvamento.
- Histórico local com consulta, ordenação recente e exclusão confirmada.
- Layout adaptável: navegação inferior em telas estreitas e NavigationRail em
  telas maiores.
- Android e Windows usam SQLite; Web usa IndexedDB do navegador.
- Os dados são separados por dispositivo/plataforma. Não há login, backend ou
  sincronização entre dispositivos.
- Leitura por câmera, códigos de barras, OCR, exportação, planos, recursos
  empresariais, anúncios e pagamentos ainda não estão implementados.

## Tecnologias

- Flutter 3.47.5 e Dart 3.13.4.
- sqflite no Android e sqflite_common_ffi no Windows.
- idb_shim para armazenamento IndexedDB na Web.
- qr para codificação e geração local de QR Codes, sem serviço de rede.
- uuid para identificadores estáveis gerados no dispositivo.

## Executar localmente

Instale Flutter 3.47.5 ou uma versão compatível com o SDK Dart declarado em
pubspec.yaml. Para obter as dependências e validar o projeto:

Neste ambiente, o SDK está em C:/Users/missp/develop/flutter, mas o
diretório bin não está no PATH. Se o terminal do VS Code não reconhecer
flutter, configure o caminho do SDK na extensão Flutter/Dart ou no PATH do
usuário.

~~~bash
flutter pub get
flutter analyze
flutter test
~~~

Inicie a Web no Chrome:

~~~bash
flutter run -d chrome
~~~

Gere uma versão estática de produção:

~~~bash
flutter build web --release
~~~

O Flutter grava o resultado em build/web. A geração do QR Code não requer
conexão de rede depois que a aplicação Web carregou. A primeira abertura ainda
precisa baixar os arquivos estáticos do site.

Para Android e Windows, consulte os requisitos de toolchain do Flutter. O
identificador Android atual (com.example.qr_ops) é provisório.

## Persistência

| Plataforma | Armazenamento | Alcance |
| --- | --- | --- |
| Android | SQLite (sqflite) | Dispositivo Android atual |
| Windows | SQLite (sqflite_common_ffi) | Perfil do Windows atual |
| Web | IndexedDB (idb_shim) | Perfil/origem do navegador atual |

Atualizar ou reabrir o mesmo navegador mantém o histórico Web enquanto os dados
locais do site não forem apagados. Navegação privada, limpeza de dados e
políticas do navegador podem remover esses registros. Não há migração entre as
plataformas e nem cópia de segurança na nuvem.

## Publicação automática no Vercel

O projeto prepara um fluxo de GitHub Actions para compilar o Flutter Web fora
do ambiente de build do Vercel e publicar o resultado pré-compilado. Isso evita
que cada deploy tente baixar o SDK completo do Flutter no Vercel.

Depois de criar/configurar o projeto no Vercel e o repositório no GitHub:

1. Cadastre no GitHub Actions os secrets VERCEL_TOKEN, VERCEL_ORG_ID e
   VERCEL_PROJECT_ID. Os valores são obtidos nas contas do proprietário e não
   devem ser colocados no código.
2. Envie o branch main ao GitHub. A ação executa análise, testes, build via
   vercel build e publicação via vercel deploy --prebuilt --prod.
3. O artefato Flutter é gerado em build/web, conforme vercel.json.

O workflow está preparado, mas a integração ainda não foi configurada nem
executada: o projeto Vercel, os secrets e o repositório remoto dependem de
configuração manual. Use o workflow como mecanismo de deploy; se o mesmo
repositório também estiver conectado ao build automático nativo do Vercel,
desative essa compilação direta para evitar uma segunda execução sem Flutter
instalado.

Arquivos relacionados: scripts/build_web.sh, vercel.json e
.github/workflows/vercel-deploy.yml.

Consulte ARCHITECTURE.md para o fluxo técnico, PROJECT_STATUS.md para validações
e limitações e CHANGELOG.md para as alterações recentes.
