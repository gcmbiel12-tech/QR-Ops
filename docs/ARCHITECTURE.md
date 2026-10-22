# QR Ops — Arquitetura

## Estado e objetivo

Aplicativo Flutter com funcionamento local/offline-first. Esta documentação descreve a arquitetura observada no código e separa capacidades existentes de itens ainda em validação. A estrutura deve ser reavaliada antes de refatorações maiores.

## Camadas e responsabilidades

- `lib/app/`: bootstrap, composição e tema do aplicativo.
- `lib/features/`: interface e fluxos por funcionalidade (`home`, `navigation`, `qr_create`, `qr_scan`, `qr_history`, `shared`).
- `lib/domain/`: modelos e contratos sem dependência de widgets. `QrRecord` e `QrRecordRepository` representam o histórico; `QrContentInterpreter` interpreta payloads sem executar ações externas.
- `lib/data/`: adaptadores de persistência. SQLite é usado em plataformas com `dart:io`; IndexedDB é usado na Web por meio da factory condicional.
- `lib/features/qr_create/`: criação, renderização e exportação; a área Criar não deve ser alterada ao trabalhar em Ler sem dependência comprovada.

## Fluxos principais

### Leitura

`QrScanPage` recebe detecções do `mobile_scanner` ou uma imagem selecionada por `image_picker` (Android/iOS). O conteúdo passa pelo `QrContentInterpreter`, é mostrado como texto bruto e pode receber uma ação contextual. Nenhuma ação externa deve ser disparada automaticamente. O resultado é persistido por `QrRecordRepository`; a navegação recebe uma notificação para atualizar o histórico.

### Histórico

`QrHistoryPage` consulta `listLatest()` no repositório existente. A busca e o filtro são aplicados em memória aos registros carregados. Exclusão individual exige confirmação. Não há sincronização em nuvem ativada pelo fluxo padrão.

### Persistência

`QrRecordRepository` é a abstração. `SqliteQrRecordRepository` e `IndexedDbQrRecordRepository` implementam o contrato. Não criar um segundo banco para o histórico. O repositório atual lista até 100 registros por padrão.

## Dependências relevantes

- `mobile_scanner`: captura/decodificação e formatos reconhecidos pelo plugin.
- `image_picker`: seleção de imagem; análise de imagem é declarada suportada no leitor para Android/iOS.
- `url_launcher`: abre ações externas somente após confirmação do usuário.
- SQLite / IndexedDB: persistência local por plataforma.

## Segurança

- Validar esquema e host antes de apresentar uma URL como ação.
- Pedir confirmação antes de abrir links, discador, e-mail, WhatsApp ou SMS.
- Nunca enviar mensagens nem conectar a redes automaticamente.
- Payloads Wi-Fi podem conter credenciais; não exibir senha em claro por padrão.
- Conteúdo desconhecido permanece copiável como texto bruto.

## Limitações conhecidas

- A leitura por imagem está limitada no código a Android/iOS; Web e Windows não devem ser declarados compatíveis com esse fluxo sem validação.
- O repositório atual não contém diretório/projeto `ios/`; portanto, iOS ainda não é um alvo de build validado neste checkout.
- O ambiente Windows usado nesta execução não tem Android SDK configurado; o build APK não pôde ser executado. O build Web foi concluído.
- Câmera Web depende de permissões e contexto seguro do navegador.
- Lanterna depende do hardware/plugin e não pode ser validada por testes widget.
- Campos comuns de vCard são apresentados; salvar/importar para a agenda não está implementado.
- Favoritos, limpeza integral do histórico e exportação CSV não estão implementados neste momento.

## Decisões arquiteturais

1. Reutilizar o repositório de histórico existente.
2. Manter interpretação como lógica de domínio sem efeitos colaterais.
3. Não realizar refatoração ampla antes de testes por plataforma.
4. Não introduzir lote, cobrança ou sincronização cloud no leitor básico.
