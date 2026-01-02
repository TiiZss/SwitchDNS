# Script para eliminar el menú contextual de SwitchDNS

$KeyPath = "HKCU:\Software\Classes\DesktopBackground\Shell\SwitchDNS"

try {
    if (Test-Path $KeyPath) {
        Remove-Item -Path $KeyPath -Recurse -Force
        Write-Host "La opción 'Alternar DNS' se ha eliminado correctamente del menú contextual." -ForegroundColor Green
    }
    else {
        Write-Host "No se encontró la entrada en el registro. Quizás ya esté eliminada." -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Error al eliminar la clave del registro: $($_.Exception.Message)"
}

Read-Host "Pulsa Enter para salir..."
