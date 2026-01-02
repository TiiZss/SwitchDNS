# SwitchDNS

<div align="center">

![GitHub release (latest by date)](https://img.shields.io/github/v/release/TiiZss/SwitchDNS?style=flat)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat)](https://opensource.org/licenses/MIT)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support%20my%20work-orange?style=flat&logo=buymeacoffee&logoColor=white)](https://www.buymeacoffee.com/tiizss)
<br>
![PowerShell](https://img.shields.io/badge/PowerShell-%235391FE.svg?style=flat&logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=flat&logo=windows&logoColor=white)

**La herramienta definitiva para gestionar tu configuración DNS en Windows.**
Cambia entre privacidad y velocidad con un solo clic.

</div>

---

## 📝 Descripción

**SwitchDNS** es una utilidad avanzada escrita en PowerShell diseñada para simplificar la gestión de servidores DNS en Windows 11. Olvídate de navegar por menús de configuración interminables. Con SwitchDNS, puedes alternar entre tus servidores DNS favoritos (como tu Pi-Hole local y Quad9) directamente desde el menú contextual de tu escritorio, o usar una interfaz de consola amigable.

## ✨ Características Principales

*   🚀 **Alternancia Instantánea**: Cambia entre dos configuraciones predefinidas (A y B) en segundos.
*   🖱️ **Integración en Escritorio**: Accede a SwitchDNS haciendo clic derecho en el fondo de tu escritorio.
*   🏷️ **Smart Labels**: El menú contextual te dice qué DNS estás usando actualmente sin tener que abrirlo.
*   🧠 **Detección Inteligente**: Detecta automáticamente tu adaptador de red activo con internet.
*   🛡️ **Backup & Restore**: Si cambias a un DNS público temporalmente, SwitchDNS recuerda tu configuración original para restaurarla después.
*   🌐 **Soporte UTF-8**: Compatible con todos los caracteres y configuraciones regionales.

## 📦 Instalación

### Requisitos Previos
*   Windows 10 o Windows 11.
*   PowerShell 5.1 o superior.
*   Permisos de Administrador (para cambiar la configuración de red).

### Configuración Rápida (Menú Contextual)

1.  Descarga el repositorio o los scripts.
2.  Haz clic derecho en `Install-ContextMenu.ps1` y selecciona **Ejecutar con PowerShell**.
3.  ¡Listo! Ahora verás la opción **"Alternar DNS..."** en el menú contextualtu escritorio.

## 🎮 Uso

### Modo Menú Contextual (Recomendado)
1.  Ve al escritorio.
2.  Haz **Clic Derecho** en el fondo (en Windows 11, pulsa *Mostrar más opciones* si no sale directo).
3.  Selecciona **SwitchDNS (Actual: ...)**.
    *   Si tenías tu DNS local -> Cambia a Quad9.
    *   Si tenías Quad9 -> Restaura tu DNS anterior.
4.  Recibirás una notificación confirmando el cambio.

### Modo Interactivo (Consola)
Ejecuta `SwitchDNS.ps1` directamente para abrir el menú completo:

```text
==================================================================
 Script para Alternar, Cambiar y Mostrar Servidor DNS (Optimizado)
==================================================================

1. Alternar DNS (192.0.2.53 <-> 9.9.9.9)
2. Configurar DNS Manualmente
3. Configurar Automático (DHCP)
4. Refrescar Vista / Cambiar Adaptador
5. Ver Todos los Adaptadores
0. Salir
```

## ⚙️ Configuración Avanzada

Puedes personalizar las direcciones IP predeterminadas editando las primeras líneas de `SwitchDNS.ps1`:

```powershell
# --- CONFIGURACIÓN GLOBAL ---
$Global:PreferredAdapterName = "Ethernet" # Nombre preferido (opcional)
$Global:ConfigA = @{ Primary = "192.0.2.53"; Secondary = "9.9.9.9" } # Tu DNS Local / Pi-Hole
$Global:ConfigB = @{ Primary = "9.9.9.9"; Secondary = "192.0.2.53" } # DNS Público / Seguro
```

## 🗑️ Desinstalación

Para eliminar la integración del menú contextual, ejecuta el script:
```powershell
.\Uninstall-ContextMenu.ps1
```

## 🤝 Contribuciones

¡Las contribuciones son bienvenidas! Si tienes ideas para mejorar el script, no dudes en abrir un Issue o un Pull Request.

## ☕ Apóyame

Si este script te ha sido útil, considera invitarme a un café. ¡Ayuda a mantener el código fluyendo!

<a href="https://www.buymeacoffee.com/tiizss" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

## 📄 Licencia

Este proyecto está bajo la Licencia MIT. Consulta el archivo `LICENSE` para más detalles.
