#     ____          _ _       _     ____  _   _ ____  
#   / ___|_      _(_) |_ ___| |__ |  _ \| \ | / ___| 
#   \___ \ \ /\ / / | __/ __| '_ \| | | |  \| \___ \ 
#    ___) \ V  V /| | || (__| | | | |_| | |\  |___) |
#   |____/ \_/\_/ |_|\__\___|_| |_|____/|_| \_|____/ 
# 
# 20250608 - TiiZss (Refactored 2026)
#
# Script PowerShell para alternar, cambiar y mostrar servidores DNS en Windows 11

param (
    [switch]$ContextMenuToggle,
    [switch]$UpdateStatus
)

# --- CONFIGURACIÓN GLOBAL ---
# Puedes editar estos valores según tus necesidades
$Global:PreferredAdapterName = "Ethernet"
$Global:ConfigA = @{ Primary = "1.1.1.1"; Secondary = "9.9.9.9" }
$Global:ConfigB = @{ Primary = "9.9.9.9"; Secondary = "1.1.1.1" }
$Global:LocalDnsIP = $null   # IP de tu DNS local (Pi-hole), solo para la etiqueta del menú
# Tus valores reales van en un fichero local que nunca se sube al repositorio:
$Global:ConfigPath = Join-Path $env:USERPROFILE ".switchdns.config.json"
$Global:BackupPath = "$env:USERPROFILE\.switchdns_backup.json"
$Global:RegKeyPath = "HKCU:\Software\Classes\DesktopBackground\Shell\SwitchDNS"
# ----------------------------

# --- CONFIGURACIÓN LOCAL (opcional) ---
if (Test-Path $Global:ConfigPath) {
    try {
        $localCfg = Get-Content -Path $Global:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($localCfg.PreferredAdapterName) { $Global:PreferredAdapterName = $localCfg.PreferredAdapterName }
        if ($localCfg.ConfigA) { $Global:ConfigA = @{ Primary = $localCfg.ConfigA.Primary; Secondary = $localCfg.ConfigA.Secondary } }
        if ($localCfg.ConfigB) { $Global:ConfigB = @{ Primary = $localCfg.ConfigB.Primary; Secondary = $localCfg.ConfigB.Secondary } }
        if ($localCfg.LocalDnsIP) { $Global:LocalDnsIP = $localCfg.LocalDnsIP }
    }
    catch {
        Write-Warning "No se pudo leer $($Global:ConfigPath): $($_.Exception.Message). Se usan los valores por defecto."
    }
}

# --- FUNCIONES ---

function Show-Logo {
    Write-Host "   ____          _ _       _     ____  _   _ ____  "
    Write-Host "  / ___|_      _(_) |_ ___| |__ |  _ \| \ | / ___| "
    Write-Host "  \___ \ \ /\ / / | __/ __| '_ \| | | |  \| \___ \ "
    Write-Host "   ___) \ V  V /| | || (__| | | | |_| | |\  |___) |"
    Write-Host "  |____/ \_/\_/ |_|\__\___|_| |_|____/|_| \_|____/ "
    Write-Host "                                         by TiiZss "
}

function Wait-UserPress {
    Read-Host "Pulsa Enter para continuar..."
}

function Test-ValidIP($ip) {
    if ([string]::IsNullOrWhiteSpace($ip)) { return $false }
    $ip = $ip.Trim()
    $ipAddress = $null
    # Utiliza validación nativa de .NET para mayor robustez
    $isValid = [System.Net.IPAddress]::TryParse($ip, [ref]$ipAddress)
    # Asegurar que es IPv4 y no IPv6 para este contexto
    if ($isValid -and $ipAddress.AddressFamily -eq 'InterNetwork') {
        return $true
    }
    return $false
}

function Show-CurrentDNS {
    param (
        [string]$AdapterName
    )
    if ([string]::IsNullOrEmpty($AdapterName)) { return }
    
    Write-Host ""
    Write-Host "--- Configuración DNS Actual para '$AdapterName' ---"
    try {
        $dnsConfig = Get-DnsClientServerAddress -InterfaceAlias $AdapterName -ErrorAction SilentlyContinue
        
        if ($null -ne $dnsConfig -and $dnsConfig.ServerAddresses.Count -gt 0) {
            Write-Host "Servidores DNS configurados:"
            foreach ($dns in $dnsConfig.ServerAddresses) {
                Write-Host "  - $dns"
            }
        }
        else {
            Write-Host "No se han configurado servidores DNS específicos (o obteniendo por DHCP)."
        }
        Write-Host "---------------------------------------------------"
    }
    catch {
        Write-Error "No se pudo obtener la configuración DNS actual: $($_.Exception.Message)"
    }
    Write-Host ""
}

function Get-MainNetworkAdapter {
    Write-Host "Identificando el adaptador de red principal..."
    
    # 1. Intentar buscar el adaptador preferido por nombre
    $adapter = Get-NetAdapter -Name $Global:PreferredAdapterName -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
    
    if ($null -ne $adapter) {
        Write-Host "Adaptador preferido encontrado: '$($adapter.Name)'."
        return $adapter
    }

    # 2. Búsqueda inteligente: Buscar adaptador Up con Default Gateway
    $ipConfigs = Get-NetIPConfiguration | Where-Object { 
        $null -ne $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up"
    }
    
    $excludeDescriptions = @("VMware", "VirtualBox", "TAP-Windows", "OpenVPN", "Hyper-V", "Pseudo-Interface")

    $candidate = $null

    foreach ($config in $ipConfigs) {
        $desc = $config.NetAdapter.InterfaceDescription
        $isVirtual = $false
        foreach ($ex in $excludeDescriptions) {
            if ($desc -match $ex) { $isVirtual = $true; break }
        }
        
        if (-not $isVirtual) {
            $candidate = $config.NetAdapter
            break
        }
    }

    # Si todos eran virtuales o no se encontró, tomar el primero activo con Gateway
    if ($null -eq $candidate -and $ipConfigs.Count -gt 0) {
        $candidate = $ipConfigs[0].NetAdapter
    }

    if ($null -ne $candidate) {
        Write-Host "Adaptador activo detectado automáticamente: '$($candidate.Name)'."
        return $candidate
    }
    
    # 3. Fallback: Primer adaptador UP que no sea virtual (sin Gateway check)
    $adapter = Get-NetAdapter | Where-Object { 
        $_.Status -eq "Up" -and $_.LinkSpeed -ne "0 Bps"
    } | Where-Object {
        $desc = $_.InterfaceDescription
        $isVirtual = $false
        foreach ($ex in $excludeDescriptions) {
            if ($desc -match $ex) { $isVirtual = $true; break }
        }
        -not $isVirtual
    } | Select-Object -First 1

    if ($null -ne $adapter) {
        Write-Host "Adaptador alternativo encontrado: '$($adapter.Name)'."
        return $adapter
    }

    Write-Warning "No se encontró ningún adaptador de red activo y físico obvio."
    return $null
}

function Update-ContextMenuLabel {
    param ([string]$AdapterName)
    if (-not (Test-Path $Global:RegKeyPath)) { return }

    $label = "Alternar DNS"
    $adapter = if ($AdapterName) { Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue } else { Get-MainNetworkAdapter }
    
    if ($adapter) {
        $dns = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -ErrorAction SilentlyContinue
        $ip = if ($dns.ServerAddresses.Count -gt 0) { $dns.ServerAddresses[0] } else { "DHCP" }
        
        # Simplificación para mostrar "Quad9" en lugar de la IP si coincide
        if ($ip -eq "9.9.9.9") { $ip = "Quad9" }
        elseif ($Global:LocalDnsIP -and $ip -eq $Global:LocalDnsIP) { $ip = "Pi-Hole/Local" }
        
        $label = "Alternar DNS (Actual: $ip)"
    }
    else {
        $label = "Alternar DNS (Sin Adaptador)"
    }
    
    try {
        Set-ItemProperty -Path $Global:RegKeyPath -Name "(Default)" -Value $label -ErrorAction SilentlyContinue
    }
    catch {}
}

function Set-DNS {
    param (
        [string]$PrimaryDNS,
        [string]$SecondaryDNS = "",
        [switch]$AutomaticDNS,
        [switch]$ToggleSpecificDNS
    )

    if ($null -eq $Global:CurrentAdapterName) {
        $adapter = Get-MainNetworkAdapter
        if ($adapter) { 
            $Global:CurrentAdapterName = $adapter.Name 
        }
        else {
            Write-Error "No hay un adaptador seleccionado. Por favor reinicia o selecciona uno."
            return
        }
    }

    $adapterName = $Global:CurrentAdapterName
    Write-Host "Aplicando cambios en adaptador: $adapterName"

    if ($AutomaticDNS) {
        Write-Host "Configurando DNS automáticamente (DHCP)..."
        try {
            Set-DnsClientServerAddress -InterfaceAlias $adapterName -ResetServerAddresses -ErrorAction Stop
            Write-Host "¡DNS configurado en automático exitosamente!" -ForegroundColor Green
        }
        catch {
            Write-Error "Error al configurar DNS en automático: $($_.Exception.Message)"
        }
    }
    elseif ($ToggleSpecificDNS) {
        Write-Host "Evaluando configuración para alternar..."
        
        $currentConfig = Get-DnsClientServerAddress -InterfaceAlias $adapterName -ErrorAction SilentlyContinue
        $currentIPs = $currentConfig.ServerAddresses

        $currPrim = if ($currentIPs.Count -ge 1) { $currentIPs[0] } else { $null }
        $currSec = if ($currentIPs.Count -ge 2) { $currentIPs[1] } else { $null }

        $newPrim = $null
        $newSec = $null
        $msg = ""

        # Lógica de Toggle usando las variables globales
        if ($currPrim -eq $Global:ConfigA.Primary -and $currSec -eq $Global:ConfigA.Secondary) {
            $newPrim = $Global:ConfigB.Primary
            $newSec = $Global:ConfigB.Secondary
            $msg = "Detectada Configuración A. Cambiando a Configuración B..."
        }
        elseif ($currPrim -eq $Global:ConfigB.Primary -and $currSec -eq $Global:ConfigB.Secondary) {
            $newPrim = $Global:ConfigA.Primary
            $newSec = $Global:ConfigA.Secondary
            $msg = "Detectada Configuración B. Cambiando a Configuración A..."
        }
        else {
            $newPrim = $Global:ConfigA.Primary
            $newSec = $Global:ConfigA.Secondary
            $msg = "Configuración desconocida. Aplicando Configuración A por defecto..."
        }

        Write-Host $msg -ForegroundColor Cyan
        Set-DNS -PrimaryDNS $newPrim -SecondaryDNS $newSec
    }
    else {
        # Configuración Manual
        if (-not (Test-ValidIP $PrimaryDNS)) {
            Write-Error "El DNS primario '$PrimaryDNS' no es válido."
            return
        }

        $dnsList = @($PrimaryDNS)
        if (-not [string]::IsNullOrEmpty($SecondaryDNS)) {
            if (Test-ValidIP $SecondaryDNS) {
                $dnsList += $SecondaryDNS
            }
            else {
                Write-Warning "El DNS secundario '$SecondaryDNS' no es válido y será ignorado."
            }
        }

        try {
            Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $dnsList -ErrorAction Stop
            Write-Host "¡DNS configurado manualmente a ($($dnsList -join ', '))!" -ForegroundColor Green
        }
        catch {
            Write-Error "Error al establecer DNS: $($_.Exception.Message)"
        }
    }

    Show-CurrentDNS -AdapterName $adapterName
    # Actualizar etiqueta tras cambio manual/interactivo
    Update-ContextMenuLabel -AdapterName $adapterName
}

function Show-AllDNS {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    $results = @()

    foreach ($adapter in $adapters) {
        $dnsConfig = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -ErrorAction SilentlyContinue
        $d1 = ""; $d2 = ""
        if ($dnsConfig -and $dnsConfig.ServerAddresses.Count -gt 0) {
            $d1 = $dnsConfig.ServerAddresses[0]
            if ($dnsConfig.ServerAddresses.Count -gt 1) { $d2 = $dnsConfig.ServerAddresses[1] }
        }
        $results += [PSCustomObject]@{
            Adaptador = $adapter.Name
            DNS1      = $d1
            DNS2      = $d2
        }
    }

    if ($results.Count -gt 0) {
        $results | Format-Table -AutoSize
    }
    else {
        Write-Host "No hay adaptadores activos."
    }
}

function Show-DNSConfigTable {
    param ([string]$AdapterName)
    if ([string]::IsNullOrEmpty($AdapterName)) { return }

    $dnsConfig = Get-DnsClientServerAddress -InterfaceAlias $AdapterName -ErrorAction SilentlyContinue
    $d1 = ""; $d2 = ""
    if ($dnsConfig -and $dnsConfig.ServerAddresses.Count -gt 0) {
        $d1 = $dnsConfig.ServerAddresses[0]
        if ($dnsConfig.ServerAddresses.Count -gt 1) { $d2 = $dnsConfig.ServerAddresses[1] }
    }
    
    [PSCustomObject]@{
        Adaptador = $AdapterName
        DNS1      = $d1
        DNS2      = $d2
    } | Format-Table -AutoSize
}

# --- LÓGICA DE EJECUCIÓN ---

# --- Comprobación de privilegios administrativos al inicio ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $IsAdmin) {
    if ($UpdateStatus) {
        Update-ContextMenuLabel
        exit
    }
    if ($ContextMenuToggle) {
        # Si se llama desde el context menu sin admin, intentar elevar
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ContextMenuToggle" -Verb RunAs
        exit
    }
    Write-Host ""
    Write-Host "¡ATENCIÓN! Este script no se está ejecutando con privilegios de administrador." -ForegroundColor Yellow
    Write-Host "Algunas funciones (cambiar DNS) NO funcionarán correctamente." -ForegroundColor Yellow
    Write-Host "Ejecuta PowerShell como Administrador para acceso completo." -ForegroundColor Yellow
    Write-Host ""
}

# --- Mode: Update Status Only ---
if ($UpdateStatus) {
    Update-ContextMenuLabel
    exit
}

# --- Mode de ejecución desde Menú Contextual ---
if ($ContextMenuToggle) {
    $adapter = Get-MainNetworkAdapter
    if (-not $adapter) {
        Add-Type -AssemblyName System.Windows.Forms
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -Id $pid).Path)
        $notify.Visible = $true
        $notify.ShowBalloonTip(3000, "Error DNS", "No se encontró adaptador activo.", [System.Windows.Forms.ToolTipIcon]::Error)
        exit
    }
    
    $adapterName = $adapter.Name
    $Global:CurrentAdapterName = $adapterName
    $currConfig = Get-DnsClientServerAddress -InterfaceAlias $adapterName -ErrorAction SilentlyContinue
    $p = if ($currConfig.ServerAddresses.Count -ge 1) { $currConfig.ServerAddresses[0] } else { $null }

    # Quad9 IPs
    $q9P = "9.9.9.9"
    $q9S = "149.112.112.112"

    Add-Type -AssemblyName System.Windows.Forms
    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -Id $pid).Path)
    $notify.Visible = $true

    try {
        if ($p -eq $q9P) {
            # Estamos en Quad9 -> Restaurar anterior
            if (Test-Path $Global:BackupPath) {
                $backup = Get-Content $Global:BackupPath | ConvertFrom-Json
                if ($backup.Mode -eq 'Auto') {
                    Set-DnsClientServerAddress -InterfaceAlias $adapterName -ResetServerAddresses -ErrorAction Stop
                    $msg = "DNS Restaurado a Automático (DHCP)."
                }
                else {
                    $ips = @($backup.Primary)
                    if ($backup.Secondary) { $ips += $backup.Secondary }
                    Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $ips -ErrorAction Stop
                    $msg = "DNS Restaurado a configuración previa."
                }
                Remove-Item $Global:BackupPath -Force
                $notify.ShowBalloonTip(3000, "SwitchDNS", $msg, [System.Windows.Forms.ToolTipIcon]::Info)
            }
            else {
                Set-DnsClientServerAddress -InterfaceAlias $adapterName -ResetServerAddresses -ErrorAction Stop
                $notify.ShowBalloonTip(3000, "SwitchDNS", "Restaurado a Automático (Sin backup).", [System.Windows.Forms.ToolTipIcon]::Info)
            }
        }
        else {
            # Ir a Quad9
            $backupObj = @{ Mode = "Manual"; Primary = $p; Secondary = $null }
            if (-not $p) { $backupObj.Mode = "Auto" }
            else { if ($currConfig.ServerAddresses.Count -gt 1) { $backupObj.Secondary = $currConfig.ServerAddresses[1] } }
            
            $backupObj | ConvertTo-Json | Set-Content $Global:BackupPath -Encoding UTF8
            
            Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses @($q9P, $q9S) -ErrorAction Stop
            $notify.ShowBalloonTip(3000, "SwitchDNS", "Activado Quad9 Secure DNS.", [System.Windows.Forms.ToolTipIcon]::Info)
        }
    }
    catch {
        $notify.ShowBalloonTip(3000, "SwitchDNS Error", "Fallo al cambiar DNS: $($_.Exception.Message)", [System.Windows.Forms.ToolTipIcon]::Error)
    }
    
    Update-ContextMenuLabel -AdapterName $adapterName

    Start-Sleep -Seconds 3
    $notify.Visible = $false
    exit
}

# --- INTERFAZ INTERACTIVA ---
Show-Logo
Write-Host "=================================================================="
Write-Host " Script para Alternar, Cambiar y Mostrar Servidor DNS (Optimizado)"
Write-Host "=================================================================="

# Detección inicial
$initialAdapter = Get-MainNetworkAdapter

if ($initialAdapter) {
    $Global:CurrentAdapterName = $initialAdapter.Name
}
else {
    Write-Warning "No se detectó adaptador automáticamente."
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    if ($adapters.Count -gt 0) {
        Write-Host "Selecciona un adaptador:"
        $i = 1
        foreach ($a in $adapters) { Write-Host "$i. $($a.Name) - $($a.InterfaceDescription)"; $i++ }
        do {
            $sel = Read-Host "Número (1-$($adapters.Count))"
        } while ($sel -as [int] -lt 1 -or $sel -as [int] -gt $adapters.Count)
        $Global:CurrentAdapterName = $adapters[[int]$sel - 1].Name
        Write-Host "Seleccionado: $Global:CurrentAdapterName"
    }
    else {
        Write-Error "No hay adaptadores disponibles. Saliendo."
        exit
    }
}

do {
    Write-Host ""
    Show-DNSConfigTable -AdapterName $Global:CurrentAdapterName
    
    $adminTag = if ($IsAdmin) { "" } else { " (Requiere Admin)" }
    $color = if ($IsAdmin) { "Green" } else { "Red" }

    Write-Host "1. Alternar DNS ($($Global:ConfigA.Primary) <-> $($Global:ConfigB.Primary))$adminTag" -ForegroundColor $color
    Write-Host "2. Configurar DNS Manualmente$adminTag" -ForegroundColor $color
    Write-Host "3. Configurar Automático (DHCP)$adminTag" -ForegroundColor $color
    Write-Host "4. Refrescar Vista / Cambiar Adaptador" -ForegroundColor Green
    Write-Host "5. Ver Todos los Adaptadores" -ForegroundColor Green
    Write-Host "0. Salir" -ForegroundColor Green
    Write-Host ""

    $choice = Read-Host "Elige una opción"

    switch ($choice) {
        "1" {
            if (-not $IsAdmin) { Write-Warning "Requiere permisos de Administrador."; Wait-UserPress; continue }
            Set-DNS -ToggleSpecificDNS
            Wait-UserPress
        }
        "2" {
            if (-not $IsAdmin) { Write-Warning "Requiere permisos de Administrador."; Wait-UserPress; continue }
            
            $publicDNS = @(
                @{ N = "Google"; P = "8.8.8.8"; S = "8.8.4.4" }
                @{ N = "Cloudflare"; P = "1.1.1.1"; S = "1.0.0.1" }
                @{ N = "Quad9"; P = "9.9.9.9"; S = "149.112.112.112" }
            )
            Write-Host "--- Referencia DNS Públicos ---"
            foreach ($p in $publicDNS) { Write-Host "$($p.N): $($p.P) / $($p.S)" }
            Write-Host "-------------------------------"

            $pDNS = Read-Host "DNS Primario"
            if (-not (Test-ValidIP $pDNS)) { Write-Error "IP Inválida."; Wait-UserPress; continue }
            
            $sDNS = Read-Host "DNS Secundario (Opcional)"
            if ($sDNS -and -not (Test-ValidIP $sDNS)) { Write-Error "IP Inválida."; Wait-UserPress; continue }

            Set-DNS -PrimaryDNS $pDNS -SecondaryDNS $sDNS
            Wait-UserPress
        }
        "3" {
            if (-not $IsAdmin) { Write-Warning "Requiere permisos de Administrador."; Wait-UserPress; continue }
            Set-DNS -AutomaticDNS
            Wait-UserPress
        }
        "4" {
            $newAdapter = Get-MainNetworkAdapter
            if ($newAdapter) { 
                $Global:CurrentAdapterName = $newAdapter.Name
                Write-Host "Adaptador actualizado a: $($newAdapter.Name)"
            }
            Wait-UserPress
        }
        "5" {
            Show-AllDNS
            Wait-UserPress
        }
        "0" { exit }
        default { Write-Host "Opción inválida." }
    }

} while ($true)