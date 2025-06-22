#     ____          _ _       _     ____  _   _ ____  
#   / ___|_      _(_) |_ ___| |__ |  _ \| \ | / ___| 
#   \___ \ \ /\ / / | __/ __| '_ \| | | |  \| \___ \ 
#    ___) \ V  V /| | || (__| | | | |_| | |\  |___) |
#   |____/ \_/\_/ |_|\__\___|_| |_|____/|_| \_|____/ 
# 
# 20250608 - TiiZss
#
# Script PowerShell para alternar, cambiar y mostrar servidores DNS en Windows 11

# --- Comprobación de privilegios administrativos al inicio ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $IsAdmin) {
    Write-Host ""
    Write-Host "¡ATENCIÓN! Este script no se está ejecutando con privilegios de administrador." -ForegroundColor Yellow
    Write-Host "Algunas funciones (cambiar DNS) NO funcionarán correctamente." -ForegroundColor Yellow
    Write-Host "Ejecuta PowerShell como Administrador para acceso completo." -ForegroundColor Yellow
    Write-Host ""
}

# Muestra el logo ASCII del script en la consola.
function Show-Logo {
    Write-Host "   ____          _ _       _     ____  _   _ ____  "
    Write-Host "  / ___|_      _(_) |_ ___| |__ |  _ \| \ | / ___| "
    Write-Host "  \___ \ \ /\ / / | __/ __| '_ \| | | |  \| \___ \ "
    Write-Host "   ___) \ V  V /| | || (__| | | | |_| | |\  |___) |"
    Write-Host "  |____/ \_/\_/ |_|\__\___|_| |_|____/|_| \_|____/ "
    Write-Host "                                         by TiiZss "
}

function Test-ValidIP($ip) {
    if ([string]::IsNullOrWhiteSpace($ip)) { return $false }
    $ip = $ip.Trim()
    # Expresión regular para formato IPv4 clásico
    if ($ip -notmatch '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') { return $false }
    $octetos = $ip -split '\.'
    foreach ($octeto in $octetos) {
        if ([int]$octeto -lt 0 -or [int]$octeto -gt 255) { return $false }
    }
    return $true
}
if (![string]::IsNullOrEmpty($PrimaryDNS) -and -not (Test-ValidIP $PrimaryDNS)) {
    Write-Error "El DNS primario no es una IP válida."
    return
}
if (![string]::IsNullOrEmpty($SecondaryDNS) -and -not (Test-ValidIP $SecondaryDNS)) {
    Write-Error "El DNS secundario no es una IP válida."
    return
}


function Show-CurrentDNS {
    param (
        [string]$AdapterName
    )
    Write-Host ""
    Write-Host "--- Configuración DNS Actual para '$AdapterName' ---"
    try {
        # Obtener los servidores DNS específicos para el adaptador dado
        $dnsConfig = Get-DnsClientServerAddress -InterfaceAlias $AdapterName -ErrorAction SilentlyContinue
        
        if ($null -ne $dnsConfig -and $dnsConfig.ServerAddresses.Count -gt 0) {
            Write-Host "Servidores DNS configurados:"
            foreach ($dns in $dnsConfig.ServerAddresses) {
                Write-Host "  - $dns"
            }
        } else {
            Write-Host "No se han configurado servidores DNS específicos en este adaptador (posiblemente obteniendo por DHCP)."
        }
        Write-Host "---------------------------------------------------"
    }
    catch {
        Write-Error "No se pudo obtener la configuración DNS actual para '$AdapterName': $($_.Exception.Message)"
    }
    Write-Host ""
}


function Get-MainNetworkAdapter {
    # Ya no mostrar advertencia aquí, solo en el inicio
    Write-Host "Identificando el adaptador de red principal..."
    
    # Define el nombre de tu adaptador físico principal para priorizarlo
    # Basado en tu 'Get-NetAdapter' output, tu adaptador físico es 'Ethernet'
    $preferredAdapterName = "Ethernet" 

    # Lista de cadenas comunes en descripciones de adaptadores virtuales/VPN para EXCLUIR
    $excludeDescriptions = @(
        "VMware Virtual Ethernet Adapter",
        "VirtualBox Host-Only Ethernet Adapter",
        "TAP-Windows Adapter V9", 
        "OpenVPN Data Channel Offload" 
    )

    # Añadir una pequeña pausa para asegurar que los adaptadores se inicialicen completamente
    Start-Sleep -Seconds 1 # Espera 1 segundo

    # 1. Intentar encontrar el adaptador preferido por nombre entre todos los activos
    $mainAdapter = Get-NetAdapter | Where-Object { 
        $_.Name -eq $preferredAdapterName -and
        $_.Status -eq "Up" -and 
        $_.LinkSpeed -ne "0 Bps" -and
        $null -eq ($excludeDescriptions | Where-Object { $_.Length -gt 0 -and $_ -ne "" -and $_.InterfaceDescription -match $_ })
    } | Select-Object -First 1

    if ($null -eq $mainAdapter) {
        Write-Host ""
        Write-Host "El adaptador preferido '$preferredAdapterName' no se encontró o no está activo/no es físico. Buscando el mejor alternativo..."
        $mainAdapter = Get-NetAdapter | Where-Object { 
            $_.Status -eq "Up" -and 
            $_.LinkSpeed -ne "0 Bps" -and
            $null -eq ($excludeDescriptions | Where-Object { $_.Length -gt 0 -and $_ -ne "" -and $_.InterfaceDescription -match $_ })
        } | Select-Object -First 1
    }

    if ($null -ne $mainAdapter) {
        Write-Host "Adaptador seleccionado: '$($mainAdapter.Name)'."
        # No validamos el Gateway aquí, lo haremos al mostrar la configuración
        return $mainAdapter
    }
    
    Write-Warning "No se encontró ningún adaptador de red activo y aparentemente físico para operar."
    return $null
}


function Set-DNS {
    param (
        [string]$PrimaryDNS,
        [string]$SecondaryDNS = "",
        [switch]$AutomaticDNS,
        [switch]$ToggleSpecificDNS
    )

    # Definir las configuraciones DNS preestablecidas
    $configA_Primary = "192.0.2.53"
    $configA_Secondary = "9.9.9.9"

    $configB_Primary = "9.9.9.9"
    $configB_Secondary = "192.0.2.53"

    # Obtener el adaptador de red principal usando la nueva función
    $networkAdapter = Get-MainNetworkAdapter

    if ($null -eq $networkAdapter) {
        Write-Error "No se pudo identificar un adaptador de red principal. No se pueden cambiar los DNS."
        return
    }

    $adapterName = $networkAdapter.Name
    Write-Host "Procediendo con el adaptador: $($adapterName)"

    if ($AutomaticDNS) {
        Write-Host "Configurando DNS automáticamente (DHCP)..."
        try {
            Set-DnsClientServerAddress -InterfaceAlias $adapterName -ResetServerAddresses
            Write-Host "¡DNS configurado en automático exitosamente!"
        }
        catch {
            Write-Error "Error al configurar DNS en automático: $($_.Exception.Message)"
        }
    }
    elseif ($ToggleSpecificDNS) {
        Write-Host "Detectando configuración DNS actual para alternar..."
        
        # Obtener los servidores DNS actuales del adaptador específico
        $currentDnsClientServerAddress = Get-DnsClientServerAddress -InterfaceAlias $adapterName -ErrorAction SilentlyContinue
        $currentDnsServers = @()
        if ($null -ne $currentDnsClientServerAddress) {
            $currentDnsServers = $currentDnsClientServerAddress.ServerAddresses
        }

        $currentPrimary = $null
        $currentSecondary = $null

        if ($currentDnsServers.Count -gt 0) {
            $currentPrimary = $currentDnsServers[0]
        }
        if ($currentDnsServers.Count -gt 1) {
            $currentSecondary = $currentDnsServers[1]
        }

        Write-Host "DNS actual Primario en '$adapterName': $($currentPrimary)"
        Write-Host "DNS actual Secundario en '$adapterName': $($currentSecondary)"

        $newPrimary = $null
        $newSecondary = $null
        $actionMessage = ""

        # Comprobar si la configuración actual coincide con Configuración A
        if (($currentPrimary -eq $configA_Primary) -and ($currentSecondary -eq $configA_Secondary)) {
            $newPrimary = $configB_Primary
            $newSecondary = $configB_Secondary
            $actionMessage = "Detectada Configuración A. Cambiando a Configuración B..."
        }
        # Comprobar si la configuración actual coincide con Configuración B
        elseif (($currentPrimary -eq $configB_Primary) -and ($currentSecondary -eq $configB_Secondary)) {
            $newPrimary = $configA_Primary
            $newSecondary = $configA_Secondary
            $actionMessage = "Detectada Configuración B. Cambiando a Configuración A..."
        }
        else {
            # Si no coincide con ninguna, aplicar la Configuración A por defecto
            $newPrimary = $configA_Primary
            $newSecondary = $configA_Secondary
            $actionMessage = "Configuración DNS actual no reconocida para alternar. Aplicando Configuración A por defecto..."
        }

        Write-Host $actionMessage
        Write-Host "Configurando nuevo DNS Primario: $newPrimary"
        Write-Host "Configurando nuevo DNS Secundario: $newSecondary"

        try {
            Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses @($newPrimary, $newSecondary)
            Write-Host "¡Servidores DNS alternados exitosamente!"
        }
        catch {
            Write-Error "Error al alternar los servidores DNS: $($_.Exception.Message)"
        }
    }
    else {
        if ([string]::IsNullOrEmpty($PrimaryDNS)) {
            Write-Error "Debes proporcionar al menos un servidor DNS primario."
            return
        }

        $dnsServers = @($PrimaryDNS)
        if (![string]::IsNullOrEmpty($SecondaryDNS)) {
            $dnsServers += $SecondaryDNS
        }

        Write-Host "Configurando DNS para '$adapterName' manualmente..."
        Write-Host "DNS Primario: $PrimaryDNS"
        if (![string]::IsNullOrEmpty($SecondaryDNS)) {
            Write-Host "DNS Secundario: $SecondaryDNS"
        }

        try {
            Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $dnsServers
            Write-Host "¡Servidores DNS configurados manualmente exitosamente!"
        }
        catch {
            Write-Error "Error al configurar los servidores DNS: $($_.Exception.Message)"
        }
    }

    # Mostrar la configuración DNS actual después de cada operación para el adaptador procesado
    Show-CurrentDNS -AdapterName $adapterName
}

function Show-AllDNS {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    $results = @()

    foreach ($adapter in $adapters) {
        $dnsConfig = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -ErrorAction SilentlyContinue
        $dns1 = ""
        $dns2 = ""
        if ($null -ne $dnsConfig -and $dnsConfig.ServerAddresses.Count -gt 0) {
            $dns1 = $dnsConfig.ServerAddresses[0]
            if ($dnsConfig.ServerAddresses.Count -gt 1) {
                $dns2 = $dnsConfig.ServerAddresses[1]
            }
        }
        # Siempre agrega el adaptador, aunque no tenga DNS configurados
        $results += [PSCustomObject]@{
            Adaptador = $adapter.Name
            DNS1      = $dns1
            DNS2      = $dns2
        }
    }

    if ($results.Count -gt 0) {
        $results | Format-Table -AutoSize
    } else {
        Write-Host "No hay adaptadores de red activos."
    }
}

# --- Función para mostrar la configuración DNS de un adaptador en formato tabla ---
function Show-DNSConfigTable {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AdapterName
    )
    $dnsConfig = Get-DnsClientServerAddress -InterfaceAlias $AdapterName -ErrorAction SilentlyContinue
    $dns1 = ""
    $dns2 = ""
    if ($null -ne $dnsConfig -and $dnsConfig.ServerAddresses.Count -gt 0) {
        $dns1 = $dnsConfig.ServerAddresses[0]
        if ($dnsConfig.ServerAddresses.Count -gt 1) {
            $dns2 = $dnsConfig.ServerAddresses[1]
        }
    }
    $result = [PSCustomObject]@{
        Adaptador = $AdapterName
        DNS1      = $dns1
        DNS2      = $dns2
    }
    $result | Format-Table -AutoSize
}

# --- Bloque de ejecución principal del script ---
#Clear-Host 
Show-Logo # Call the function to display the ASCII art
Write-Host "=================================================================="
Write-Host " Script para Alternar, Cambiar y Mostrar Servidor DNS (Windows 11)"
Write-Host "=================================================================="
    
# Detección inicial del adaptador principal
$initialNetworkAdapter = Get-MainNetworkAdapter

# Si no se detecta automáticamente, permitir selección manual
if ($null -eq $initialNetworkAdapter) {
    Write-Host ""
    Write-Warning "No se detectó un adaptador principal automáticamente."
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    if ($adapters.Count -eq 0) {
        Write-Error "No hay adaptadores de red activos disponibles."
        exit
    }
    Write-Host "Selecciona un adaptador de red de la siguiente lista:"
    $i = 1
    foreach ($adapter in $adapters) {
        Write-Host "$i. $($adapter.Name) - $($adapter.InterfaceDescription)"
        $i++
    }
    do {
        $sel = Read-Host "Introduce el número de adaptador (1-$($adapters.Count))"
        $isValid = ($sel -as [int]) -and $sel -ge 1 -and $sel -le $adapters.Count
        if (-not $isValid) { Write-Host "Selección no válida. Intenta de nuevo." }
    } while (-not $isValid)
    $initialNetworkAdapter = $adapters[$sel - 1]
    Write-Host "Adaptador seleccionado: $($initialNetworkAdapter.Name)"
}

do {
    
    # Muestra la configuración DNS actual aquí para el adaptador detectado
    if ($null -ne $initialNetworkAdapter) {
        Show-DNSConfigTable -AdapterName $initialNetworkAdapter.Name
    } else {
        Write-Warning "No se pudo identificar un adaptador de red principal."
        Write-Warning "Asegúrate de que tu adaptador '$preferredAdapterName' esté activo o selecciona un adaptador manualmente si persisten los problemas."
    }

    # Menú coloreado según privilegios
    if ($IsAdmin) {
        Write-Host "1. Alternar entre 192.0.2.53/9.9.9.9 y 9.9.9.9/192.0.2.53" -ForegroundColor Green
        Write-Host "2. Configurar DNS Manualmente (otros valores)" -ForegroundColor Green
        Write-Host "3. Configurar DNS Automáticamente (DHCP)" -ForegroundColor Green
        Write-Host "4. Mostrar configuración DNS actual (Actualizar vista)" -ForegroundColor Green
        Write-Host "5. Mostrar DNS de todos los adaptadores" -ForegroundColor Green
        Write-Host "0. Salir" -ForegroundColor Green
    } else {
        Write-Host "1. Alternar entre 192.0.2.53/9.9.9.9 y 9.9.9.9/192.0.2.53" -ForegroundColor Red
        Write-Host "2. Configurar DNS Manualmente (otros valores)" -ForegroundColor Red
        Write-Host "3. Configurar DNS Automáticamente (DHCP)" -ForegroundColor Red
        Write-Host "4. Mostrar configuración DNS actual (Actualizar vista)" -ForegroundColor Green
        Write-Host "5. Mostrar DNS de todos los adaptadores" -ForegroundColor Green
        Write-Host "0. Salir" -ForegroundColor Green
    }
    Write-Host ""

    $choice = Read-Host "Elige una opción (0-5)"

    switch ($choice) {
        "1" {
            if (-not $IsAdmin) {
                Write-Host "Necesitas ejecutar el script como administrador para utilizar esta opción." -ForegroundColor Yellow
            } else {
                Set-DNS -ToggleSpecificDNS
            }
            Read-Host "Pulsa Enter para continuar..."
        }
        "2" {
            if (-not $IsAdmin) {
                Write-Host "Necesitas ejecutar el script como administrador para utilizar esta opción." -ForegroundColor Yellow
                Read-Host "Pulsa Enter para continuar..."
                continue
            }
            # Mostrar tabla de servidores DNS públicos
            $publicDNS = @(
                [PSCustomObject]@{ Proveedor = "Google";        DNS1 = "8.8.8.8";         DNS2 = "8.8.4.4" }
                [PSCustomObject]@{ Proveedor = "Cloudflare";    DNS1 = "1.1.1.1";         DNS2 = "1.0.0.1" }
                [PSCustomObject]@{ Proveedor = "Quad9";         DNS1 = "9.9.9.9";         DNS2 = "149.112.112.112" }
                [PSCustomObject]@{ Proveedor = "OpenDNS";       DNS1 = "208.67.222.222";  DNS2 = "208.67.220.220" }
                [PSCustomObject]@{ Proveedor = "Comodo Secure"; DNS1 = "8.26.56.26";      DNS2 = "8.20.247.20" }
                [PSCustomObject]@{ Proveedor = "CleanBrowsing"; DNS1 = "185.228.168.9";   DNS2 = "185.228.169.9" }
                [PSCustomObject]@{ Proveedor = "Yandex.DNS";    DNS1 = "77.88.8.8";       DNS2 = "77.88.8.1" }
                [PSCustomObject]@{ Proveedor = "Neustar DNS";   DNS1 = "156.154.70.1";    DNS2 = "156.154.71.1" }
                [PSCustomObject]@{ Proveedor = "AdGuard DNS";   DNS1 = "94.140.14.14";    DNS2 = "94.140.15.15" }
            )
            Write-Host ""
            Write-Host "Servidores DNS públicos recomendados:"
            $publicDNS | Format-Table -AutoSize
            Write-Host ""

            # Validar DNS primario al introducirlo (máximo 3 intentos)
            $maxTries = 3
            $try = 0
            $dnsPrimary = ""
            do {
                $dnsPrimary = Read-Host "Introduce el servidor DNS Primario (Ej: 8.8.8.8)"
                $try++
                if (-not (Test-ValidIP $dnsPrimary)) {
                    Write-Host "El DNS primario no es una IP válida." -ForegroundColor Red
                    if ($try -ge $maxTries) {
                        Write-Host "Has superado el número máximo de intentos. No se aplican cambios. Volviendo al menú..." -ForegroundColor Yellow
                        Read-Host "Pulsa Enter para continuar..."
                        continue
                    }
                }
            } while (-not (Test-ValidIP $dnsPrimary) -and $try -lt $maxTries)

            # Si después de 3 intentos el DNS primario sigue siendo inválido, volver al menú
            if (-not (Test-ValidIP $dnsPrimary)) {
                continue
            }

            # Solo preguntar por el DNS secundario si el primario es válido
            $maxTriesSec = 3
            $trySec = 0
            $dnsSecondary = ""
            do {
                $dnsSecondary = Read-Host "Introduce el servidor DNS Secundario (Opcional, Ej: 8.8.4.4). Deja en blanco si no quieres uno."
                $trySec++
                if ($dnsSecondary -and -not (Test-ValidIP $dnsSecondary)) {
                    Write-Host "El DNS secundario no es una IP válida." -ForegroundColor Red
                    if ($trySec -ge $maxTriesSec) {
                        Write-Host "Has superado el número máximo de intentos. No se aplican cambios. Volviendo al menú..." -ForegroundColor Yellow
                        Read-Host "Pulsa Enter para continuar..."
                        continue
                    }
                }
            } while ($dnsSecondary -and -not (Test-ValidIP $dnsSecondary) -and $trySec -lt $maxTriesSec)

            # Si el DNS secundario sigue siendo inválido después de 3 intentos, volver al menú
            if ($dnsSecondary -and -not (Test-ValidIP $dnsSecondary)) {
                continue
            }

            # Confirmar antes de aplicar el cambio
            Write-Host ""
            Write-Host "Vas a aplicar la siguiente configuración DNS:"
            Write-Host "  DNS Primario:   $dnsPrimary"
            if ($dnsSecondary) {
                Write-Host "  DNS Secundario: $dnsSecondary"
            }
            $confirm = Read-Host "¿Quieres aplicar estos cambios? (S/N)"
            if ($confirm -notin @('S','s','Y','y','Sí','si','SI')) {
                Write-Host "No se realizaron cambios. Volviendo al menú..."
                Read-Host "Pulsa Enter para continuar..."
                continue
            }

            Set-DNS -PrimaryDNS $dnsPrimary -SecondaryDNS $dnsSecondary

            # Mostrar la configuración DNS actual en formato tabla después de configurar manualmente
            if ($null -ne $initialNetworkAdapter) {
                Show-DNSConfigTable -AdapterName $initialNetworkAdapter.Name
            } else {
                Write-Warning "No se pudo identificar un adaptador de red principal."
            }

            Read-Host "Pulsa Enter para continuar..."
        }
        "3" {
            if (-not $IsAdmin) {
                Write-Host "Necesitas ejecutar el script como administrador para utilizar esta opción." -ForegroundColor Yellow
            } else {
                Set-DNS -AutomaticDNS
            }
            Read-Host "Pulsa Enter para continuar..."
        }
        "4" { 
            Write-Host "Actualizando la vista de la configuración DNS..."
            $initialNetworkAdapter = Get-MainNetworkAdapter 
            if ($null -ne $initialNetworkAdapter) {
                Show-DNSConfigTable -AdapterName $initialNetworkAdapter.Name
            } else {
                Write-Warning "No se pudo identificar un adaptador de red principal."
            }
            Read-Host "Pulsa Enter para continuar..."
        }
        "5" {
            Show-AllDNS
            Read-Host "Pulsa Enter para continuar..."
        }
        "0" {
            Write-Host "Saliendo del script. ¡Adiós!"
            exit
        }
        default {
            Write-Host "Opción no válida. Por favor, elige un número entre 0 y 5."
            Read-Host "Pulsa Enter para continuar..."
        }
    }
} while ($true)