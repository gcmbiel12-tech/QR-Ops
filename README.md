# QR Ops

Aplicativo Flutter em português para criar QR Codes e organizar um histórico local. A versão Web inicial funciona em navegadores de computadores e celulares.

## Estado atual

- Criação local de QR Codes a partir de texto ou endereço, com validação e prévia antes do salvamento.
- Histórico local com consulta, ordenação recente e exclusão confirmada.
- Layout adaptável: navegação inferior em telas estreitas e NavigationRail em telas maiores.
- Android e Windows usam SQLite; Web usa IndexedDB do navegador.
- Os dados são separados por dispositivo/plataforma. Não há login, backend ou sincronização entre dispositivos.
- Leitura por câmera, códigos de barras, OCR, exportação, planos, recursos empresariais, anúncios e pagamentos ainda não estão implementados.

## Tecnologias

- Flutter 3.47.5 e Dart 3.13.4.
- sqflite no Android e sqflite_common_ffi no Windows.
- idb_shim para armazenamento IndexedDB na Web.
- qr para codificação e geração local de QR Codes, sem serviço de rede.
- uuid para identificadores estáveis gerados no dispositivo.

## Executar localmente

Instale Flutter 3.47.5 ou uma versão compatível com o SDK Dart declarado em `pubspec.yaml`. Para obter as dependências e validar o projeto:

```bash
flutter pub get
flutter analyze
flutter test
```

Inicie a Web no Chrome:

```bash
flutter run -d chrome
```

Gere uma versão estática de produção:

```bash
flutter build web --release
```

O Flutter grava o resultado em `build/web`. A geração do QR Code não requer conexão de rede depois que a aplicação Web carregou. A primeira abertura ainda precisa baixar os arquivos estáticos do site.

Para Android e Windows, consulte os requisitos de toolchain do Flutter. O identificador Android atual (`com.example.qr_ops`) é provisório.

## Persistência

| Plataforma | Armazenamento | Alcance |
| --- | --- | --- |
| Android | SQLite (sqflite) | Dispositivo Android atual |
| Windows | SQLite (sqflite_common_ffi) | Perfil do Windows atual |
| Web | IndexedDB (idb_shim) | Perfil/origem do navegador atual |

Atualizar ou reabrir o mesmo navegador mantém o histórico Web enquanto os dados locais do site não forem apagados. Navegação privada, limpeza de dados e políticas do navegador podem remover esses registros. Não há migração entre as plataformas e nem cópia de segurança na nuvem.

## Publicação automática no Vercel

O projeto prepara um fluxo de GitHub Actions para compilar o Flutter Web fora do ambiente de build do Vercel e publicar o resultado pré-compilado.

Depois de configurar o projeto no Vercel e o repositório no GitHub:

1. Cadastre no GitHub Actions os secrets `VERCEL_TOKEN`, `VERCEL_ORG_ID` e `VERCEL_PROJECT_ID`.
2. Envie o branch `main` ao GitHub.
3. Confira o workflow em `.github/workflows/vercel-deploy.yml` e valide a compilação e publicação.

Os valores dos secrets não devem ser colocados no código. O projeto Vercel, os secrets e o workflow dependem de configuração e validação manual.

Arquivos relacionados: `scripts/build_web.sh`, `vercel.json` e `.github/workflows/vercel-deploy.yml`.

Consulte `ARCHITECTURE.md` para o fluxo técnico, `PROJECT_STATUS.md` para validações e limitações e `CHANGELOG.md` para as alterações recentes.
