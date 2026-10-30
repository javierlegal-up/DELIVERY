@echo off
rem Inicia el servidor local de LUNK para verla en esta PC y en un celular del mismo Wi-Fi.
rem No requiere instalar Python ni Node.js. Toda la logica esta en servidor.ps1.
rem Bypass aplica solo a esta ejecucion: no cambia la configuracion de Windows.

title Sol Delivery - Servidor local
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0servidor.ps1"

echo.
echo El servidor se detuvo. Si ves un error arriba, enviale una captura a Claude.
pause
