$p = 'C:\Users\gcmbi\Documents\Projetos\QR Ops\lib\features\qr_scan\qr_scan_page.dart'
$s = [System.IO.File]::ReadAllText($p)
$replacements = @{
'cÃ¢mera'='câmera'; 'cÃ³digos'='códigos'; 'cÃ³digo'='código'; 'serÃ¡'='será'; 'vocÃª'='você'; 'nÃ£o'='não'; 'NÃ£o'='Não'; 'disponÃ­vel'='disponível'; 'aplicativo'='aplicativo'; 'compatÃ­vel'='compatível'; 'utiliza'='utiliza'; 'interrompida'='interrompida'; 'possÃ­vel'='possível'; 'permissÃ£o'='permissão'; 'PermissÃµes'='Permissões'; 'permissÃµes'='permissões'; 'configuraÃ§Ãµes'='configurações'; 'configuraÃ§Ã£o'='configuração'; 'Ã '='à'; 'Ã¡'='á'; 'Ã£'='ã'; 'Ã§'='ç'; 'Ãµ'='õ'; 'Ã©'='é'; 'Ãª'='ê'; 'Ã­'='í'; 'Ã³'='ó'; 'Ãº'='ú'; 'Ã‰'='É'; 'inicializaÃ§Ã£o'='inicialização'; 'Conte\u00FAdo'='Conteúdo'
}
foreach ($key in $replacements.Keys) { $s = $s.Replace($key, $replacements[$key]) }
$s = $s.Replace('Leia QR Codes e códigos de barras. A câmera só será iniciada quando você solicitar.', 'Aponte a câmera para um QR Code ou código de barras.')
$s = $s.Replace('Mantenha o código dentro da área da câmera. A leitura será interrompida após o reconhecimento.', 'Posicione o código na área da câmera para fazer a leitura.')
$s = $s.Replace('No navegador, permita o acesso à câmera. O site precisa estar em HTTPS ou em um contexto seguro compatível, como localhost.', 'Permita o acesso à câmera quando o navegador solicitar.')
$s = $s.Replace('A câmera não está disponível no executável Windows. Use o aplicativo Android ou a versão Web do QR Ops para utilizar uma câmera.', 'A leitura pela câmera não está disponível nesta versão do Windows. Use o QR Ops no navegador ou em um dispositivo compatível.')
[System.IO.File]::WriteAllText($p, $s, [System.Text.UTF8Encoding]::new($false))
