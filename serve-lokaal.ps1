# Mini static webserver (geen Node/Python nodig) - serveert deze map op http://localhost:3010
# Root "/" toont app.html (het bestand dat we lokaal bewerken). Ctrl+C of venster sluiten = stoppen.
$port = 3010
$root = $PSScriptRoot
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
try { $listener.Start() }
catch { Write-Host "Kon poort $port niet openen: $_" -ForegroundColor Red; Read-Host "Enter om te sluiten"; exit 1 }

Write-Host "Offerte-app draait lokaal op http://localhost:$port/  (sluit dit venster om te stoppen)" -ForegroundColor Green
Start-Process "http://localhost:$port/"

$mime = @{ ".html"="text/html; charset=utf-8"; ".js"="text/javascript"; ".mjs"="text/javascript"; ".css"="text/css"; ".svg"="image/svg+xml"; ".json"="application/json"; ".png"="image/png"; ".jpg"="image/jpeg"; ".jpeg"="image/jpeg"; ".webp"="image/webp"; ".ico"="image/x-icon"; ".woff"="font/woff"; ".woff2"="font/woff2"; ".ttf"="font/ttf" }

while ($listener.IsListening) {
  try {
    $ctx = $listener.GetContext()
    $path = [System.Uri]::UnescapeDataString($ctx.Request.Url.LocalPath).TrimStart('/')
    if ([string]::IsNullOrEmpty($path)) { $path = "app.html" }
    $file = Join-Path $root $path
    if ((Test-Path $file -PathType Leaf) -and ($file.StartsWith($root))) {
      $ext = [System.IO.Path]::GetExtension($file).ToLower()
      $ct = $mime[$ext]; if (-not $ct) { $ct = "application/octet-stream" }
      $bytes = [System.IO.File]::ReadAllBytes($file)
      $ctx.Response.Headers.Add("Cache-Control","no-store")
      $ctx.Response.ContentType = $ct
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $ctx.Response.StatusCode = 404
    }
    $ctx.Response.Close()
  } catch { }
}
