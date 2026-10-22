# QR Ops — Matriz de funcionalidades

Legenda: **Implementado (automatizado)** = código e testes automatizados; **Parcial / validar plataforma** = existe implementação, mas falta validar hardware/plataforma; **Planejado** = não implementado.

| Área | Funcionalidade | Estado | Observações |
|---|---|---|---|
| Criar | Geração e personalização de QR | Implementado (automatizado) | Não alterar durante trabalho do leitor sem dependência comprovada. |
| Criar | Exportação PNG em resoluções suportadas | Implementado (automatizado) | Testes existentes cobrem exportação. |
| Ler | Captura por câmera | Parcial / validar plataforma | Widget tests não validam câmera física. |
| Ler | Pausa após leitura e leitura novamente | Implementado (automatizado) | Coberto por testes do leitor; falta hardware real. |
| Ler | Lanterna e troca de câmera | Parcial / validar plataforma | Depende de hardware e capacidades reportadas pelo plugin. |
| Ler | Seleção e análise de imagem | Parcial / validar plataforma | Código restringe análise de imagem a Android/iOS; validar arquivos inválidos/cancelamento em dispositivos. |
| Ler | Interpretação de URL, telefone, e-mail, WhatsApp, Wi-Fi, vCard, SMS e texto | Implementado (automatizado) | Ações externas exigem confirmação; Wi-Fi não conecta automaticamente. |
| Histórico | Persistência local por SQLite/IndexedDB | Implementado (automatizado) | Confirmar reinicialização em plataformas reais. |
| Histórico | Busca e filtro por criado/lido | Implementado; teste de interface pendente | Filtro em memória sobre os últimos 100 registros carregados. |
| Histórico | Excluir registro individual | Implementado | Exige confirmação. |
| Histórico | Favoritos e limpar tudo | Planejado | Contrato atual não possui operações para essas ações. |
| Profissional | Leitura em lote, sessão e exportação CSV | Planejado | Não incluir no leitor básico. |
| Plataforma | Câmera Web | Parcial / validar plataforma | Requer permissão e contexto de navegador compatível; build Web passou. |
| Plataforma | Android | Parcial / validar plataforma | Código presente; build APK bloqueado pela ausência de Android SDK neste ambiente. |
| Plataforma | iOS | Não validado neste checkout | Não existe diretório `ios/`; requer gerar/configurar alvo iOS e validar em macOS/dispositivo. |
| Plataforma | Câmera/galeria Windows | Não suportado pelo fluxo atual | Não declarar suporte sem implementação e testes próprios. |
| Cloud | Sincronização e cobrança | Desativado / não aprovado | Não ativar sem autorização. |

## Critério de status

Uma funcionalidade não é considerada concluída só por haver código: deve passar testes relevantes, documentar limites de plataforma e, quando depender de hardware, ter evidência de teste físico. Os estados desta tabela devem ser atualizados a cada release.
