# SwitchDNS

![GitHub release (latest by date)](https://img.shields.io/github/v/release/TiiZss/SwitchDNS)
![GitHub license](https://img.shields.io/github/license/TiiZss/SwitchDNS)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support%20my%20work-orange?style=flat&logo=buymeacoffee&logoColor=white)](https://www.buymeacoffee.com/tiizss)


Script PowerShell avanzado para gestionar cambiar y alternar servidores DNS en Windows 11 de forma rápida y sencilla.

## Características

*   **Alternancia Rápida**: Cambia entre una configuración DNS personalizada (ej. Pi-Hole) y DNS públicos (ej. Quad9) con un solo comando.
*   **Integración en Menú Contextual**: Haz clic derecho en el escritorio para alternar el DNS sin abrir consolas.
    *   Muestra el estado actual del DNS directamente en el menú (ej. "Alternar DNS (Actual: Quad9)").
*   **Detección Inteligente**: Identifica automáticamente el adaptador de red activo principal.
*   **Configuración y Restauración**: Guarda tu configuración actual antes de cambiar y la restaura automáticamente.
*   **Soporte UTF-8**: Manejo correcto de caracteres especiales.

## Instalación del Menú Contextual

Para añadir la opción al menú de clic derecho del escritorio:

1.  Ejecuta el script `Install-ContextMenu.ps1` con PowerShell.
    ```powershell
    .\Install-ContextMenu.ps1
    ```
2.  ¡Listo! Ahora verás la opción **"Alternar DNS..."** al hacer clic derecho en el fondo del escritorio.

Para eliminarlo, simplemente ejecuta `Uninstall-ContextMenu.ps1`.

## Uso Manual

Puedes ejecutar el script principal `SwitchDNS.ps1` directamente para acceder al menú interactivo:

```powershell
.\SwitchDNS.ps1
```

### Opciones del Menú
1.  **Alternar DNS**: Cambia entre tus configuraciones A y B definidas.
2.  **Configurar Manualmente**: Establece servidores DNS específicos.
3.  **Automático (DHCP)**: Restablece la configuración a automática.
4.  **Refrescar/Ver**: Muestra la configuración actual de todos los adaptadores.

## Configuración

Puedes editar las variables al inicio de `SwitchDNS.ps1` para personalizar tus servidores preferidos:

```powershell
$Global:ConfigA = @{ Primary = "192.0.2.53"; Secondary = "9.9.9.9" }
$Global:ConfigB = @{ Primary = "9.9.9.9"; Secondary = "192.0.2.53" }
```
