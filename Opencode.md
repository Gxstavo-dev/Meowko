# Tareas pendientes de Meowko

Este archivo es para que opencode lo lea y haga las tareas **una por una**.

## Contexto

Meowko es un widget de Wayland hecho en QML (Quickshell) que funciona como una "Dynamic Island" en el panel superior y chatea con opencode.

- Archivo principal: `meowko.qml` (plantilla; `shell.qml` es la copia de trabajo y está en `.gitignore`).
- El gato está en `components/Cat.qml`, los GIFs (`gato_dormido.gif` / `gato_tranquilo.gif`) y el ícono en `assets/`, y el resto de los componentes visuales en `components/` (`Eyes`, `Header`, `MessageList`, `UserBubble`, `AiMessage`, `ThinkingDots`, `InputBar`).
- Cada mensaje lanza `opencode run --format json` y se parsea al terminar el proceso.
- Documentación: `README.md`. Los comentarios del código van en inglés y explican el _porqué_.

## Reglas de trabajo

1. Haz **una sola tarea por vez**, en el orden de la lista. No adelantes trabajo de otras tareas.
2. Antes de empezar, lee el código local (el que está en la computadora del usuario, en su carpeta de trabajo) y parte de él, no de GitHub. Si la tarea ya está implementada (parcial o totalmente), verifícala y complétala en vez de reescribirla.
3. No inventes flags ni subcomandos de opencode. Compruébalos con `opencode run --help`, `opencode --help` y la documentación en https://opencode.ai/docs/cli.
4. No introduzcas rutas hardcodeadas de usuario. Usa `homePath`.
5. Pasa los argumentos al shell como parámetros posicionales (`"$0"`, `"$@"`), nunca interpolados en el string.
6. Al terminar cada tarea:
   - arranca con `quickshell` y revisa que no haya errores de QML en la consola;
   - actualiza `README.md` (referencia, estructura y comandos);
   - marca la casilla aquí (`- [x]`);
   - haz un commit con un mensaje claro **en la rama `meowko`** y súbelo con `git push origin meowko`;
   - **detente** y resume qué hiciste y qué probaste. Espera confirmación antes de seguir.
7. **Nunca** hagas commit ni push a `main`, ni hagas merge. Todo el trabajo va en la rama `meowko`.
8. Si algo no se puede verificar (por ejemplo, el formato de salida de un subcomando), dilo explícitamente en vez de suponerlo.

## Tareas

### Preparación

- [x] **0. Crear la rama `meowko`.**
      Desde `main`: `git checkout -b meowko` y `git push -u origin meowko`. A partir de aquí todo avance se commitea y se sube a esa rama. No toques `main`.

- [x] **1. Reorganizar los archivos.**
      Es una refactorización pura: **no cambia ninguna funcionalidad ni el aspecto**. El objetivo es que el código sea más legible y mantenible en lugar de un solo archivo de unas 800 líneas.

  1. Renombra `meowkow.qml` a `meowko.qml` con `git mv` (el nombre actual es un typo) y corrige todas las referencias en el proyecto.
  2. Crea la carpeta `assets/` y mueve ahí los GIFs (`gato_dormido.gif`, `gato_tranquilo.gif`) y la imagen `gato_icon.png`, usando `git mv` para conservar el historial. Actualiza las rutas de `source` en el QML y en el README.
  3. Crea la carpeta `components/`. Cada componente visual que hoy vive dentro de `meowko.qml` pasa a su propio archivo `.qml` (nombre en PascalCase), y el archivo principal solo los importa y los usa. Mueve también `Cat.qml` ahí. División sugerida; ajústala si el código real pide otra:
     - `Eyes.qml`: los ojitos y su animación de parpadeo.
     - `Header.qml`: ID de sesión, "nuevo", modelo/agente, volumen y cerrar.
     - `MessageList.qml`: el `ListView` y su `Connections`.
     - `UserBubble.qml`, `AiMessage.qml` (con el botón de copiar) y `ThinkingDots.qml`: las piezas del `delegate`.
     - `InputBar.qml`: el gato, el campo de texto y el placeholder.
     - `Cat.qml`: el gato.
     - Si ya existen en el código, también `SysMessage.qml`, `CommandPopup.qml` y `StopButton.qml`.
  4. Se queda en `meowko.qml`: el `ShellRoot`, el estado, los helpers, la lógica de opencode (`send`, `handleOutput`, `Process`), el `ListModel`, el `Variants`/`PanelWindow` y el `box` animado (incluido el `mask: Region`).
  5. Importa los componentes con `import "components"` en el archivo principal. Los archivos dentro de una misma carpeta se ven entre sí sin importar.
  6. Los componentes **no deben depender de ids externos** como `root` o `win`. Pásales lo que necesiten con propiedades (colores, textos, `busy`, señales como `onSendRequested`, etc.). Considera un `Theme.qml` para la paleta y la tipografía; solo hazlo como singleton si compruebas que funciona en Quickshell, y si no, pásala como propiedades.
  7. Ten en cuenta que las rutas relativas de `source` (GIFs) se resuelven respecto al archivo `.qml` que las usa: desde `components/Cat.qml` la ruta será `../assets/...`.
  8. Actualiza el README: la sección "Estructura del proyecto", la instalación (ahora hay que copiar también `components/` y `assets/`, p. ej. `cp -r meowko.qml components assets ~/.config/quickshell/` y renombrar a `shell.qml`) y las referencias de "Referencia de `meowko.qml`" y "Referencia de `Cat.qml`". Revisa también `.gitignore`.
  9. Verifica que el widget se ve y se comporta **exactamente igual** que antes: abrir/cerrar, ojitos, parpadeo de alerta, puntitos, copiar, volumen, "nuevo", enviar y recibir un mensaje. Comprueba que `meowko.qml` quedó claramente más corto.

### Funciones de chat

Estas tareas parten del código local, el que está en la computadora del usuario. Impleméntalas tú desde cero según lo descrito y pruébalas.

- [x] **2. Mostrar el modelo activo.**
      El encabezado muestra modelo y agente activos (o "modelo por defecto"). Se guardan en `~/.local/state/meowko-prefs` (JSON) y se leen al arrancar con `try/catch`.

- [x] **3. Comandos con `/` y autocompletado.**
      Los mensajes que empiezan con `/` los resuelve el widget y no se envían a opencode. Popup de sugerencias sobre el input; `Tab` completa; clic en una sugerencia la inserta. Comandos mínimos: `/help`, `/new`, `/clear`, `/mute`. Los avisos se muestran como filas de rol `sys` (texto gris, plano).

- [x] **4. Cambiar de modelo.**
      `/model` muestra el activo, `/model <proveedor/modelo>` lo cambia (acepta un fragmento si solo coincide uno), `/model default` lo quita. `/models [filtro]` lista los disponibles con `opencode models`. El modelo se pasa con `--model` en cada petición. El catálogo lo trae el `Process` `lister`, fresco en cada consulta.

- [ ] **5. Cancelar una petición.**
      Se cancela pulsando **`Esc` dos veces** seguidas (no `Ctrl+C`):
  - El primer `Esc` con una petición en curso **no** cierra el widget: arma la cancelación y muestra un aviso breve junto al input ("Esc de nuevo para cancelar").
  - Un segundo `Esc` dentro de 1,5 s cancela. Si pasa ese tiempo, la cancelación se desarma.
  - Sin petición en curso, `Esc` sigue cerrando el widget; con el popup de comandos abierto, solo lo descarta.
  - Además: un botón ■ junto al input y `/cancel`, que cancelan de inmediato.
  - Al cancelar, envía `SIGINT` (`proc.signal(2)`, el equivalente a `Ctrl+C` para el proceso); si sigue vivo tras 2 s, escala a `SIGTERM`.
  - Conserva el texto parcial y lo marca como _(cancelado)_, sin sonido ni parpadeo.
  - Comprueba que el `exec` en el `sh -c` hace que la señal llegue a opencode y que no queden procesos huérfanos (`pgrep -a opencode`).

- [ ] **6. Elegir agente.**
      `/agent [nombre]` muestra o cambia el agente (`--agent`), `/agent default` lo quita, `/agents` lista con `opencode agent list`. Si es posible, valida el nombre contra esa lista.

- [ ] **7. Cambiar de sesión.**
      `/sessions` lista con `opencode session list` y `/session <id>` continúa una sesión (`--session`). Comprueba el formato real de salida y, si ayuda, mejora cómo se muestra.

- [ ] **8. Directorio de trabajo.**
      `/cd <ruta>` cambia `workingDirectory` del proceso (soporta `~`), se guarda en las preferencias y abre una conversación nueva, porque las sesiones pertenecen a un proyecto. Valida que la ruta exista y avisa si no.

- [ ] **9. Detectar opencode automáticamente.**
      Resolver el binario con `command -v opencode` dentro del `sh -c` y usar `opencodeBin` (ruta de bun) solo como respaldo. Probarlo arrancando Quickshell desde el autostart del compositor, donde el `PATH` suele ser corto.

### Funciones nuevas

- [ ] **10. Streaming.**
      **Primero investiga:** ejecuta `opencode run --format json "..."` y comprueba cuántos eventos `type: "text"` emite y cuándo (¿uno por mensaje o varios mientras genera?). Si solo emite uno, documenta que mostrar la respuesta en vivo no aporta, pero **igualmente migra a lectura por líneas** (`SplitParser`), porque la tarea 11 la necesita. Si emite varios, migra de `StdioCollector` a `SplitParser` (separador `\n`) y actualiza el último mensaje de la IA a medida que llegan las líneas. Mantén la compatibilidad con la cancelación y el guardado del `sessionID`.

- [ ] **11. Mostrar avisos de uso excedido y de reintento.**
      Cuando se supera el límite del plan gratuito, la TUI de opencode muestra un aviso del estilo `Free usage exceeded, subscribe to Go [retrying in 8m 32s attempt #1]`. En el widget hoy no se ve nada: solo los puntitos de "pensando" durante minutos y, al final, un error genérico o nada. Ese aviso (y cualquier otro de reintento o error del proveedor) debe mostrarse.
  1. **Investiga primero** qué emite `opencode run --format json` en esa situación: ¿un evento JSON con otro `type` (error, estado de reintento)?, ¿texto suelto?, ¿nada hasta que termina? Ten en cuenta que `stderr` ya se mezcla en `stdout` con `2>&1` y que `handleOutput()` hoy descarta toda línea que no empieza con `{`. Si no puedes reproducir el límite, pide una captura real de la salida en vez de suponer el formato, y documenta lo que encuentres.
  2. Requiere lectura **incremental** por líneas (`SplitParser`, ver tarea 10): el aviso tiene que verse mientras el proceso sigue vivo, no al terminar.
  3. Muestra el mensaje completo, con la cuenta atrás y el número de intento, en el widget (por ejemplo, sustituyendo los puntitos o como fila `sys` que se actualiza en lugar de repetirse). El gato debe seguir en estado "trabajando" mientras dure el reintento.
  4. Si el proceso termina por un error de límite o de proveedor, muestra ese mensaje en lugar de "(sin respuesta, código N)".
  5. Debe poder cancelarse con el mismo mecanismo de la tarea 5 durante la espera.

- [ ] **12. Mostrar el historial al retomar una sesión.**
      Hoy, al reiniciar el widget o usar `/session`, opencode recuerda la conversación pero el widget no la muestra. Investiga si hay una forma de leerla (`opencode export`, el servidor HTTP o los archivos de sesión en disco). Si existe, cárgala en el `ListModel` al arrancar y en `/session`. Si no, documenta la limitación.

- [ ] **13. Entrada multilínea e historial.**
      `Shift+Enter` inserta un salto de línea y `Enter` envía. Flecha arriba/abajo recorre los mensajes enviados antes (solo cuando el cursor está en la primera/última línea). Probablemente haya que pasar de `TextInput` a `TextEdit` y hacer que el input crezca con un tope de alto.

- [ ] **14. Bloques de código con botón de copiar.**
      Detectar los bloques de código del Markdown de la respuesta y mostrar un botón de copiar propio en cada uno. Además, hacer que el copiar general no se lleve el markdown crudo (`**`, backticks). Debe mantener el aspecto actual del resto de la respuesta.

- [ ] **15. Adjuntar archivos.**
      **Primero comprueba** con `opencode run --help` si existe un flag para adjuntar archivos (`--file` / `-f`). Si existe, añade un comando `/attach <ruta>` (o arrastrar y soltar, si Quickshell lo permite) que lo pase en la siguiente petición y muestre los adjuntos pendientes encima del input. Si no existe, documenta que no se puede.

- [ ] **16. Atajo global para abrir y cerrar el widget.**
      Quickshell no tiene atajos por sí mismo en todos los compositores. Usa `IpcHandler` de Quickshell para exponer un `toggle`, de modo que se invoque con `quickshell ipc call ...` desde un keybind del compositor. Documenta el keybind para Hyprland (clásico y Lua) en el README. Debe abrir en el monitor activo y enfocar el input.

- [ ] **17. Arranque más rápido.**
      Hoy se lanza un proceso de opencode nuevo por mensaje. Investiga `opencode serve` junto con `opencode run --attach <url>` para mantener un servidor persistente. Mide la latencia antes y después. Si la mejora es clara, impleméntalo con arranque y cierre del servidor gestionados por el widget y con una opción para desactivarlo. Si no lo es, documenta el resultado.

## Notas

- Si dos tareas chocan (por ejemplo, 10 y 13 tocan el input y el procesamiento de salida), pregunta antes de decidir.
- Si una tarea resulta inviable, déjala marcada con la razón en vez de forzarla.
