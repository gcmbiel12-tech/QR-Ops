# QR Ops — Guia de desenvolvimento

## Ambiente

- Flutter/Dart compatível com a versão definida em `pubspec.yaml`.
- No ambiente Windows de referência, Flutter está em `C:\src\flutter\bin`.
- Executar comandos na raiz do repositório.

## Comandos de validação

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub test/features/qr_scan/qr_scan_page_test.dart
flutter test --no-pub test/domain/qr_content_interpreter_test.dart
flutter build web --release --no-pub
```

A compilação Web não substitui testes em dispositivos. Registrar separadamente testes manuais e os dispositivos/navegadores usados.

## Fluxo de trabalho obrigatório

1. Consultar `git status --short` e `git log -1 --oneline`.
2. Ler os arquivos relevantes e o diff existente antes de editar.
3. Preservar toda alteração local preexistente e todo arquivo não rastreado.
4. Fazer mudanças pequenas, formatar os arquivos alterados e executar testes específicos.
5. Executar `flutter analyze --no-pub`, `flutter test --no-pub` e `git diff --check` antes de concluir uma fase.
6. Revisar `git diff` e documentar limitações.
7. Não executar `git reset`, `git clean` nem reverter alterações alheias.
8. Não fazer commit, push ou deploy sem autorização específica.

## Convenções

- UI e navegação em `lib/features/`.
- Regras puras e modelos em `lib/domain/`.
- Persistência e APIs em `lib/data/`.
- Injetar repositórios nos widgets; não acessar o banco diretamente pela interface.
- Interpretadores de payload não podem executar ações externas.
- Toda ação externa deve ser iniciada por escolha explícita do usuário.

## Compatibilidade

Não inferir suporte apenas porque o projeto compila. Câmera, lanterna, galeria e permissões devem ser validadas em dispositivos/plataformas reais. Registrar claramente o que foi automatizado e o que foi testado manualmente.

## Git

Scripts auxiliares locais podem não fazer parte do produto. Revisar individualmente os arquivos staged antes de qualquer commit. Commits e pushes exigem autorização do responsável.
