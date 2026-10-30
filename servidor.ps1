# Servidor local de LUNK. No requiere instalar nada: usa solo lo que ya trae Windows.
# Se inicia con iniciar-lunk.bat. Este archivo se mantiene sin acentos a proposito:
# PowerShell 5 puede leerlos mal si el archivo no tiene marca de codificacion.

param([int]$Puerto = 8080)

$ErrorActionPreference = 'Stop'

# Solo se sirven estos archivos. Cualquier otra cosa de la carpeta queda inaccesible.
$archivos = @{
    '/'                     = @('index.html', 'text/html; charset=utf-8')
    '/index.html'           = @('index.html', 'text/html; charset=utf-8')
    '/manifest.webmanifest' = @('manifest.webmanifest', 'application/manifest+json; charset=utf-8')
    '/sw.js'                = @('sw.js', 'text/javascript; charset=utf-8')
    '/icon.svg'             = @('icon.svg', 'image/svg+xml')
}

function Obtener-IpLocal {
    # Primero, el adaptador con salida a internet (normalmente, el Wi-Fi)
    try {
        $red = Get-NetIPConfiguration |
            Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
            Select-Object -First 1
        if ($red) { return @($red.IPv4Address)[0].IPAddress }
    } catch { }

    # Plan B: cualquier IPv4 que no sea interna del propio equipo
    try {
        $direcciones = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName())
        foreach ($direccion in $direcciones) {
            if ($direccion.AddressFamily -eq 'InterNetwork' -and -not $direccion.ToString().StartsWith('127.')) {
                return $direccion.ToString()
            }
        }
    } catch { }

    return $null
}

function Crear-PaginaQr {
    # El QR se dibuja en la misma PC: la direccion no se envia a ningun servicio externo.
    # Solo se descarga la libreria que lo genera.
    $urlCelular = if ($ip) { "http://${ip}:$Puerto" } else { '' }
    $textoDireccion = if ($ip) { $urlCelular } else { 'No se encontro la IP de esta PC. Revisa que este conectada al Wi-Fi.' }

    return @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>QR para probar en el celular</title>
<style>
  body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
         background: #071033; color: #fff; font-family: system-ui, 'Segoe UI', sans-serif; text-align: center; }
  main { padding: 24px; max-width: 480px; }
  h1 { margin: 0 0 8px; font-size: 28px; }
  p { margin: 8px 0; color: #C3CCEB; font-size: 16px; line-height: 1.5; }
  #qr { display: inline-block; margin: 16px 0; padding: 8px; min-width: 200px; background: #fff; color: #071033; border-radius: 16px; }
  #qr svg { display: block; }
  code { color: #FFC400; font-size: 20px; font-weight: 700; word-break: break-all; }
  a { color: #FFC400; font-weight: 700; }
</style>
</head>
<body>
<main>
  <h1>Escanea con el celular</h1>
  <p>El celular debe estar en el mismo Wi-Fi que esta PC.</p>
  <div id="qr">Generando QR...</div>
  <p><code>$textoDireccion</code></p>
  <p><a href="/">Abrir la app en esta PC</a></p>
</main>
<script src="https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.js"></script>
<script>
  var url = '$urlCelular';
  var caja = document.getElementById('qr');
  try {
    if (!url) throw new Error('Sin IP');
    var qr = qrcode(0, 'M');
    qr.addData(url);
    qr.make();
    caja.innerHTML = qr.createSvgTag(8, 16);
  } catch (error) {
    caja.textContent = 'No se pudo generar el QR. Escribe a mano la direccion de abajo.';
  }
</script>
</body>
</html>
"@
}

function Responder($cliente) {
    $flujo = $cliente.GetStream()
    $flujo.WriteTimeout = 5000

    $bufer = New-Object byte[] 8192
    $leidos = $flujo.Read($bufer, 0, $bufer.Length)
    $primeraLinea = ([System.Text.Encoding]::ASCII.GetString($bufer, 0, $leidos) -split "`r`n")[0]
    $partes = $primeraLinea -split ' '
    $metodo = $partes[0]
    $ruta = if ($partes.Length -ge 2) { ($partes[1] -split '\?')[0] } else { '' }

    $estado = '404 Not Found'
    $tipo = 'text/plain; charset=utf-8'
    $cuerpo = [System.Text.Encoding]::UTF8.GetBytes('No encontrado')

    if ($metodo -ne 'GET' -and $metodo -ne 'HEAD') {
        $estado = '405 Method Not Allowed'
        $cuerpo = [System.Text.Encoding]::UTF8.GetBytes('Metodo no permitido')
    } elseif ($ruta -eq '/qr') {
        $estado = '200 OK'
        $tipo = 'text/html; charset=utf-8'
        $cuerpo = [System.Text.Encoding]::UTF8.GetBytes((Crear-PaginaQr))
    } elseif ($archivos.ContainsKey($ruta)) {
        $estado = '200 OK'
        $tipo = $archivos[$ruta][1]
        $cuerpo = [System.IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $archivos[$ruta][0]))
    } else {
        # Imagenes: solo .webp directamente dentro de fotos/ o marcas/, sin subcarpetas
        $rutaImagen = [System.Uri]::UnescapeDataString($ruta)
        if ($rutaImagen -match '^/(fotos|marcas)/[^/\\:]+\.webp$') {
            $archivoImagen = Join-Path $PSScriptRoot $rutaImagen.TrimStart('/')
            if ([System.IO.File]::Exists($archivoImagen)) {
                $estado = '200 OK'
                $tipo = 'image/webp'
                $cuerpo = [System.IO.File]::ReadAllBytes($archivoImagen)
            }
        }
    }

    # no-cache: cada cambio que guardes se ve al recargar la pagina
    $cabeceras = "HTTP/1.1 $estado`r`n" +
        "Content-Type: $tipo`r`n" +
        "Content-Length: $($cuerpo.Length)`r`n" +
        "Cache-Control: no-cache`r`n" +
        "Connection: close`r`n`r`n"
    $bytesCabeceras = [System.Text.Encoding]::ASCII.GetBytes($cabeceras)

    $flujo.Write($bytesCabeceras, 0, $bytesCabeceras.Length)
    if ($metodo -ne 'HEAD') { $flujo.Write($cuerpo, 0, $cuerpo.Length) }
    $flujo.Flush()

    Write-Host ("  {0}  {1}  {2}" -f (Get-Date -Format 'HH:mm:ss'), $estado.Substring(0, 3), $ruta)
}

# --- Abre el puerto. Si esta ocupado, prueba los siguientes ---
$servidor = $null
for ($intento = 0; $intento -lt 10; $intento++) {
    try {
        $candidato = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, ($Puerto + $intento))
        $candidato.Start()
        $servidor = $candidato
        $Puerto = $Puerto + $intento
        break
    } catch { }
}

if (-not $servidor) {
    Write-Host "No se pudo abrir ningun puerto entre $Puerto y $($Puerto + 9)." -ForegroundColor Red
    exit 1
}

# --- Muestra las direcciones ---
$ip = Obtener-IpLocal

Write-Host ''
Write-Host '  ==========================================================' -ForegroundColor Green
Write-Host '   Sol Delivery esta corriendo' -ForegroundColor Green
Write-Host '  ==========================================================' -ForegroundColor Green
Write-Host ''
Write-Host "   En esta PC:    http://127.0.0.1:$Puerto"
if ($ip) {
    Write-Host "   En el celular: http://${ip}:$Puerto" -ForegroundColor Yellow
    Write-Host ''
    Write-Host '   El celular debe estar en el MISMO Wi-Fi que esta PC.'
    Write-Host '   Si Windows pregunta por el Firewall, pulsa "Permitir acceso".'
} else {
    Write-Host '   No se encontro la IP de esta PC. Revisa que este conectada al Wi-Fi.'
}
Write-Host ''
Write-Host '   Para detenerlo, cierra esta ventana o pulsa Ctrl+C.'
Write-Host '  ==========================================================' -ForegroundColor Green
Write-Host ''

# Abre la pagina con el QR para escanearlo con el celular
Start-Process "http://127.0.0.1:$Puerto/qr"

# --- Atiende las conexiones ---
# Los navegadores suelen abrir conexiones que quedan en espera sin pedir nada.
# Por eso cada una se atiende solo cuando ya envio datos, para que no frene a las demas.
$conexiones = New-Object System.Collections.ArrayList

try {
    while ($true) {
        while ($servidor.Pending()) {
            [void]$conexiones.Add(@{ Cliente = $servidor.AcceptTcpClient(); Inicio = Get-Date })
        }

        foreach ($conexion in @($conexiones)) {
            $terminada = $false
            try {
                if ($conexion.Cliente.Available -gt 0) {
                    Responder $conexion.Cliente
                    $terminada = $true
                } elseif (((Get-Date) - $conexion.Inicio).TotalSeconds -gt 10) {
                    $terminada = $true
                }
            } catch {
                # Un error en una conexion no debe detener el servidor
                $terminada = $true
            }

            if ($terminada) {
                $conexion.Cliente.Close()
                $conexiones.Remove($conexion)
            }
        }

        Start-Sleep -Milliseconds 20
    }
} finally {
    $servidor.Stop()
}
