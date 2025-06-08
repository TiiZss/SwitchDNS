#     ____          _ _       _     ____  _   _ ____  
#   / ___|_      _(_) |_ ___| |__ |  _ \| \ | / ___| 
#   \___ \ \ /\ / / | __/ __| '_ \| | | |  \| \___ \ 
#    ___) \ V  V /| | || (__| | | | |_| | |\  |___) |
#   |____/ \_/\_/ |_|\__\___|_| |_|____/|_| \_|____/ 
# 
# 20250608 - TiiZss
#
# Script PowerShell para alternar, cambiar y mostrar servidores DNS en Windows 11

function Show-Logo {
    Write-Host "   ____          _ _       _     ____  _   _ ____  "
    Write-Host "  / ___|_      _(_) |_ ___| |__ |  _ \| \ | / ___| "
    Write-Host "  \___ \ \ /\ / / | __/ __| '_ \| | | |  \| \___ \ "
    Write-Host "   ___) \ V  V /| | || (__| | | | |_| | |\  |___) |"
    Write-Host "  |____/ \_/\_/ |_|\__\___|_| |_|____/|_| \_|____/ "
    Write-Host "                                         by TiiZss "
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
        ($excludeDescriptions | ForEach-Object { $_ -notin $_.InterfaceDescription }) # Excluye si la descripción contiene alguna de las palabras clave
    } | Select-Object -First 1

    if ($null -eq $mainAdapter) {
        Write-Host "El adaptador preferido '$preferredAdapterName' no se encontró o no está activo/no es físico. Buscando el mejor alternativo..."
        # Si el preferido no está disponible o no es válido, toma el primero de la lista filtrada
        $mainAdapter = Get-NetAdapter | Where-Object { 
            $_.Status -eq "Up" -and 
            $_.LinkSpeed -ne "0 Bps" -and
            ($excludeDescriptions | ForEach-Object { $_ -notin $_.InterfaceDescription }) 
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

# --- Bloque de ejecución principal del script ---
#Clear-Host 
Show-Logo # Call the function to display the ASCII art
Write-Host "=================================================================="
Write-Host " Script para Alternar, Cambiar y Mostrar Servidor DNS (Windows 11)"
Write-Host "=================================================================="
Write-Host "" 
    
# Detección inicial del adaptador principal
$initialNetworkAdapter = Get-MainNetworkAdapter

do {
    
    # Muestra la configuración DNS actual aquí para el adaptador detectado
    if ($null -ne $initialNetworkAdapter) {
        Show-CurrentDNS -AdapterName $initialNetworkAdapter.Name
    } else {
        Write-Warning "No se pudo identificar un adaptador de red principal."
        Write-Warning "Asegúrate de que tu adaptador '$preferredAdapterName' esté activo o selecciona un adaptador manualmente si persisten los problemas."
    }
    
    Write-Host "" 
    Write-Host "1. Alternar entre 192.0.2.53/9.9.9.9 y 9.9.9.9/192.0.2.53"
    Write-Host "2. Configurar DNS Manualmente (otros valores)"
    Write-Host "3. Configurar DNS Automáticamente (DHCP)"
    Write-Host "4. Mostrar configuración DNS actual (Actualizar vista)"
    Write-Host "5. Salir"
    Write-Host ""

    $choice = Read-Host "Elige una opción (1-5)"

    switch ($choice) {
        "1" {
            Set-DNS -ToggleSpecificDNS
            Read-Host "Pulsa Enter para continuar..."
        }
        "2" {
            $dnsPrimary = Read-Host "Introduce el servidor DNS Primario (Ej: 8.8.8.8)"
            $dnsSecondary = Read-Host "Introduce el servidor DNS Secundario (Opcional, Ej: 8.8.4.4). Deja en blanco si no quieres uno."
            Set-DNS -PrimaryDNS $dnsPrimary -SecondaryDNS $dnsSecondary
            Read-Host "Pulsa Enter para continuar..."
        }
        "3" {
            Set-DNS -AutomaticDNS
            Read-Host "Pulsa Enter para continuar..."
        }
        "4" { 
            Write-Host "Actualizando la vista de la configuración DNS..."
            # Re-evalúa el adaptador principal para mostrar la información más reciente
            $initialNetworkAdapter = Get-MainNetworkAdapter 
            Read-Host "Pulsa Enter para continuar..."
        }
        "5" {
            Write-Host "Saliendo del script. ¡Adiós!"
            exit
        }
        default {
            Write-Host "Opción no válida. Por favor, elige un número entre 1 y 5."
            Read-Host "Pulsa Enter para continuar..."
        }
    }
} while ($true)