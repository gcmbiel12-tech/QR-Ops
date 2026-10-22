# QR Ops — Refinamento visual e WhatsApp

## Personalização visual
- A biblioteca de estilos fica em `lib/features/qr_create/qr_visual_config.dart`.
- A área de personalização apresenta paletas prontas em círculos e uma roda de tonalidades para escolher a cor do QR e a cor de fundo.
- Cores inseridas por HEX continuam disponíveis como opção avançada. Toda combinação é validada com contraste mínimo de 4,5:1.
- Há modelos por categoria e molduras desenhadas no preview e no PNG: clássica, flores, folhas botânicas, estrelas, corações, confetes e moldura com texto.
- Só a opção “Moldura com texto” mostra um campo editável; as demais molduras não inserem textos prontos.
- O PNG continua renderizado diretamente em 256, 512, 1024 ou 2048 px. A matriz codificada não é alterada pelo estilo.

## QR de WhatsApp
- O tipo WhatsApp recebe telefone internacional (com + e código do país) e uma mensagem opcional.
- O QR codifica uma URL `https://wa.me/<telefone>?text=<mensagem codificada>`. Ao escanear, o WhatsApp abre a conversa e apresenta a mensagem pré-preenchida; a pessoa ainda precisa enviá-la.
- O usuário deve confirmar que o número informado tem uma conta ativa no WhatsApp. A aplicação não consulta nem valida a conta remotamente.

## Validação
Executar da raiz do projeto:

```powershell
C:\src\flutter\bin\flutter.bat analyze --no-pub
C:\src\flutter\bin\flutter.bat test --no-pub
C:\src\flutter\bin\flutter.bat build web --release --no-pub
```

A leitura de QR deve ser verificada após alterações ao desenho das molduras. Um teste bem-sucedido em uma combinação não garante leitura universal para todos os dispositivos, impressões ou logos.
