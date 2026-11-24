# mvp_lego — Simulador Educativo de Mecanismos LEGO Technic / EV3

Prototipo MVP de un simulador educativo de robótica/mecatrónica escolar inspirado en **LEGO MINDSTORMS EV3 / Technic** y en la experiencia visual de **BrickLink Studio**, construido con un núcleo de simulación en **C++20** separado del motor visual **Godot 4.7**.

---

## Estado actual: ¿Qué está implementado y qué es trabajo futuro?

### Funcionalidades implementadas (MVP)
- **Núcleo cinemático independiente en C++20 (`brain/`):**
  - Modelo tipado de dominio (`Motor`, `Shaft`, `Gear`, `Wheel`) sin dependencias de Godot.
  - Grafo de conexiones (`ConnectionGraph`) con validación explícita de puertos (`RotationalAxis`, `GearTeeth`), rechazo de dientes `<= 0`, IDs inexistentes, autoconexiones y conexiones duplicadas.
  - Solver cinemático determinista (`KinematicSolver`) por búsqueda en anchura desde el motor:
    - Acoplamiento coaxial (`+1:1`).
    - Engrane externo (`omega_salida = -omega_entrada * (dientes_entrada / dientes_salida)`).
    - Detección de mecanismos desconectados, múltiples motores o ciclos cinemáticamente conflictivos.
    - Soporte de modo estricto (`Strict`, usado en pruebas unitarias) y modo parcial (`PartialConnected`, usado en el editor Studio para girar lo conectado al motor y reportar piezas sueltas).
  - Pruebas unitarias automatizadas con **CTest** (34 verificaciones).
- **Adaptador GDExtension (`gdextension/`):**
  - Nodo `OpenSimNode` compilado con `godot-cpp` (`10.0.0-stable`, API `4.7`).
  - Expone control de simulación (`start`, `stop`, `reverse_direction`, `set_target_rpm`), edición de mecanismo y consulta de RPMs/errores desde GDScript sin duplicar lógica mecánica.
- **Editor 3D interactivo tipo Studio (`app/`):**
  - Renderizador `gl_compatibility` sobre Godot 4.7.2.
  - 6 piezas esenciales a escala proporcional LEGO (`1 stud = 0.40 m`): **Motor EV3**, **Viga Technic 1x7** (con 7 huecos pasantes reales), **Eje 5L**, **Engranaje 24T** (con 4 ventanas reales), **Engranaje 8T** y **Rueda Technic**.
  - Cámara orbital 360° (incluye vista por debajo de la grilla), desplazamiento espacial con `Espacio + Click derecho`, selección individual o múltiple por cuadro de arrastre, movimiento en bloque con cajas de colisión 3D, rotación con `R`, borrado con `Supr` y tren de ejemplo precargado.

### Limitaciones conocidas y trabajo futuro (fuera de alcance en este MVP)
- **Sin dinámica física completa (Jolt Physics):** la simulación es cinemática determinista en banco de trabajo; las ruedas giran a sus RPM calculadas, pero aún no impulsan un vehículo rodando por el suelo ni simulan gravedad, torque, fricción o colisiones dinámicas.
- **Sin análisis de estabilidad estructural:** las vigas actúan como soporte geométrico en la escena; no se calcula flexión ni resistencia mecánica.
- **Sin catálogo LDraw completo:** las piezas actuales son geometría procedural proporcional al estándar LEGO Technic; la importación de piezas `.dat` LDraw y sus atribuciones queda para una fase posterior.
- **Sin sensores, programación por bloques ni guardado/carga:** sensores EV3, seguidores de línea en pista, editor por bloques y persistencia de proyectos forman parte de etapas posteriores.
- **Hardware escolar objetivo:** la compatibilidad con equipos antiguos (por ejemplo Intel HD previos a OpenGL 3.3, 4 GB RAM, disco mecánico) requiere pruebas reales sobre el equipo objetivo; en Windows con drivers OpenGL antiguos puede requerirse `--rendering-driver opengl3_angle`.

---

## Estructura del proyecto

```text
mvp/
├── CMakeLists.txt
├── README.md
├── .gitignore
├── brain/                      # Nucleo C++20 puro (sin tipos de Godot)
│   ├── CMakeLists.txt
│   ├── include/opensim/
│   │   ├── Types.hpp
│   │   ├── Components.hpp
│   │   ├── ConnectionGraph.hpp
│   │   ├── KinematicSolver.hpp
│   │   └── Simulation.hpp
│   ├── src/
│   │   ├── ConnectionGraph.cpp
│   │   ├── KinematicSolver.cpp
│   │   └── Simulation.cpp
│   └── tests/
│       └── test_kinematics.cpp
├── gdextension/                # Adaptador Godot <-> C++
│   ├── CMakeLists.txt
│   ├── godot-cpp/              # Submodulo/clon local (ignorado en Git)
│   └── src/
│       ├── OpenSimNode.hpp
│       ├── OpenSimNode.cpp
│       ├── register_types.h
│       └── register_types.cpp
└── app/                        # Frontend Godot 4.7 (gl_compatibility)
    ├── project.godot
    ├── opensim.gdextension
    ├── scenes/
    │   └── main.tscn
    └── scripts/
        ├── lego_meshes.gd
        ├── main.gd
        └── smoke_test.gd
```

## Convención matemática y de signos

Para dos engranajes externos en contacto:

`omega_salida = -omega_entrada * (dientes_entrada / dientes_salida)`

Unidades: revoluciones por minuto (RPM) en el núcleo; radianes por segundo (RPM * 2π / 60) únicamente para animar visualmente en Godot.

Convención de signos (regla de la mano derecha sobre eje local +Z):

- `+RPM`: giro antihorario visto desde +Z.
- `-RPM`: giro horario visto desde +Z.

Ejemplo de referencia (24T conductor, 8T conducido):

- Entrada +60 RPM -> Salida -180 RPM.
- Invertir giro (-60 RPM) -> Salida +180 RPM.
- Detener simulación -> Salidas a 0 RPM conservando intacto el ensamblaje.

## Requisitos verificados (entorno de desarrollo)

- Sistema operativo probado: Windows 11 (x86_64)
- Compilador C++20: g++ 16.2.0 (MinGW-W64 UCRT)
- Build: CMake 4.4.4, Ninja
- Python: Python 3.10+ / 3.15 (requerido en tiempo de compilación por godot-cpp)
- Git: 2.46+
- Motor: Godot 4.7.2-stable
- Bindings: godot-cpp tag 10.0.0-stable

## Preparación inicial (requiere internet una sola vez)

Desde la carpeta `mvp/`:

```powershell
git clone --depth 1 --branch 10.0.0-stable https://github.com/godotengine/godot-cpp.git gdextension/godot-cpp
```

Una vez clonado godot-cpp y compilada la extensión, el proyecto se compila y ejecuta 100 % sin internet.

## Compilación, pruebas y ejecución (comandos verificados)

### 1. Compilar y probar solo el núcleo C++20 (sin Godot)

```powershell
cmake -S . -B build_core -G Ninja -DCMAKE_BUILD_TYPE=Debug -DOPENSIM_BUILD_GDEXTENSION=OFF
cmake --build build_core
ctest --test-dir build_core --output-on-failure -V
```

### 2. Compilar núcleo + GDExtension (app/bin/opensim_gdext.dll) y probar

Cierra Godot antes de recompilar en Windows para evitar bloqueo sobre la DLL.

```powershell
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure -V
```

### 3. Prueba de integración headless con Godot 4.7.2

```powershell
$godotConsole = "C:\Dev\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
& $godotConsole --headless --path app --script res://scripts/smoke_test.gd
```

### 4. Ejecutar el Editor 3D interactivo

```powershell
& $godotConsole --path app
```

## Controles del Editor 3D

- Click derecho + arrastrar: orbitar 360° (incluye vista desde abajo de la grilla).
- Espacio + Click derecho (o botón central) + arrastrar: mover cámara en todos los ejes.
- Rueda del mouse: zoom.
- Panel izquierdo: seleccionar una de las 6 piezas o volver a modo Seleccionar / Mover (Esc).
- Click izquierdo en vacío + arrastrar: selección múltiple por cuadro.
- Click izquierdo sobre pieza(s) + arrastrar: mover pieza o grupo respetando colisiones.
- `R`: rotar 90°. | `Supr`: eliminar selección.