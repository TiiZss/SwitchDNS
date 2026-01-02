# Script para instalar el menú contextual de SwitchDNS
# Requiere permisos de Administrador

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $IsAdmin) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ScriptPath = "d:\Scripts\SwitchDNS\SwitchDNS.ps1"

if (-not (Test-Path $ScriptPath)) {
    Write-Error "No se encuentra el script principal en $ScriptPath"
    Pause
    exit
}

$KeyPath = "HKCU:\Software\Classes\DesktopBackground\Shell\SwitchDNS"
$CommandPath = "$KeyPath\command"
$MenuText = "Alternar DNS (Quad9 / Restaurar)"
$IconPath = "imageres.dll,26" # Icono de red generico

try {
    Write-Host "Creando claves de registro..."
    
    # Crear clave principal
    if (-not (Test-Path $KeyPath)) {
        New-Item -Path $KeyPath -Force | Out-Null
    }
    
    # Establecer texto e icono
    Set-ItemProperty -Path $KeyPath -Name "(Default)" -Value $MenuText
    Set-ItemProperty -Path $KeyPath -Name "Icon" -Value $IconPath
    Set-ItemProperty -Path $KeyPath -Name "Position" -Value "Top" # Opcional: ponerlo arriba

    # Crear clave de comando
    if (-not (Test-Path $CommandPath)) {
        New-Item -Path $CommandPath -Force | Out-Null
    }

    # Comando de ejecución: Llama a PowerShell, oculto (-WindowStyle Hidden), ejecutando el script con el flag -ContextMenuToggle
    $ExecuteCommand = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`" -ContextMenuToggle"
    Set-ItemProperty -Path $CommandPath -Name "(Default)" -Value $ExecuteCommand

    Write-Host "¡Instalación completada con éxito!" -ForegroundColor Green
    Write-Host "Actualizando estado inicial..."
    powershell.exe -ExecutionPolicy Bypass -File "$ScriptPath" -UpdateStatus
    
    Write-Host "Ahora deberías ver la opción '$MenuText' (o con el estado actual) al hacer clic derecho en el escritorio."
}
catch {
    Write-Error "Error al modificar el registro: $($_.Exception.Message)"
}

Read-Host "Pulsa Enter para salir..."
