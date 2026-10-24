$root = 'C:\Users\gcmbi\Documents\Projetos\QR Ops\build\web'
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add('http://localhost:8080/')
$listener.Start()
Write-Output 'QR Ops server listening on http://localhost:8080'
while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
  if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'index.html' }
  $file = Join-Path $root $rel
  if (-not (Test-Path $file -PathType Leaf)) { $file = Join-Path $root 'index.html' }
  try {
    $bytes = [System.IO.File]::ReadAllBytes($file)
    $ext = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
    $ctx.Response.ContentType = switch ($ext) { '.html' {'text/html'} '.js' {'text/javascript'} '.json' {'application/json'} '.css' {'text/css'} '.wasm' {'application/wasm'} '.svg' {'image/svg+xml'} '.png' {'image/png'} '.ico' {'image/x-icon'} default {'application/octet-stream'} }
    $ctx.Response.StatusCode = 200
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  } catch { $ctx.Response.StatusCode = 500 }
  $ctx.Response.Close()
}