<div align="center">

# 🪟 smalt

### A window, an event queue, a clock, a 2-D drawing surface with text, 3D maths and a complete software renderer — written entirely in [**Axle**](https://axle-lang.dev)

**Not a binding.** There is no `SDL2.dll` to copy, no vcpkg prefix to find, no `[link]` section to fill in. smalt speaks Win32, X11 and Wayland itself, and rasterises every triangle on the CPU.

<p align="center">
  <a href="https://axle-lang.dev"><img alt="Powered by Axle" src="https://img.shields.io/badge/powered%20by-Axle-5B4BE1?style=for-the-badge&labelColor=1b1b2b"></a>
  <a href="https://axle-lang.dev"><img alt="Axle 0.12.0+" src="https://img.shields.io/badge/axle-0.12.0%2B-5B4BE1?style=for-the-badge&labelColor=1b1b2b"></a>
</p>
<p align="center">
  <img alt="Rendering: 100% CPU" src="https://img.shields.io/badge/rendering-100%25%20CPU-FF7A45?style=flat-square&labelColor=1b1b2b">
  <img alt="Dependencies: none" src="https://img.shields.io/badge/dependencies-none-2E7D32?style=flat-square&labelColor=1b1b2b">
  <img alt="Backends: Win32, X11, Wayland" src="https://img.shields.io/badge/backends-Win32%20%C2%B7%20X11%20%C2%B7%20Wayland-1D6FB8?style=flat-square&labelColor=1b1b2b">
  <img alt="Unsafe: at the OS edge only" src="https://img.shields.io/badge/unsafe-OS%20edge%20only-9C27B0?style=flat-square&labelColor=1b1b2b">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555555?style=flat-square&labelColor=1b1b2b">
</p>

<sub><a href="#-at-a-glance">At a glance</a> · <a href="#-highlights">Highlights</a> · <a href="#-quick-start">Quick start</a> · <a href="#%EF%B8%8F-coming-from-sdl">Coming from SDL</a> · <a href="#%EF%B8%8F-architecture">Architecture</a> · <a href="#%EF%B8%8F-how-it-works">How it works</a> · <a href="https://axle-lang.dev">Axle ↗</a></sub>

</div>

---

![A textured cube on a tiled floor, lit and depth-tested, in a Win32 window at 60 fps](doc/spinning_cube.png)

<div align="center"><em>The 3D pipeline: a textured cube over a perspective-correct tiled floor, Blinn-Phong lit and depth-tested — every triangle rasterised on the CPU, in a window Axle opened itself.</em></div>

<table>
<tr>
<td width="33%"><img alt="A shaded, z-buffered torus rendered by hand into the framebuffer" src="doc/donut3d.png"></td>
<td width="33%"><img alt="A 2D platformer drawing straight into the window framebuffer" src="doc/mario3d.png"></td>
<td width="33%"><img alt="A drifting colour gradient filling the window" src="doc/hello_window.png"></td>
</tr>
<tr>
<td align="center"><em><code>donut3d</code> — its own renderer</em></td>
<td align="center"><em><code>mario3d</code> — framebuffer only</em></td>
<td align="center"><em><code>hello_window</code> — the smallest one</em></td>
</tr>
</table>

> **smalt** *(n.)* — a deep blue pigment made by grinding cobalt glass to powder.
> Glass, ground down until it is something you can paint with. That is the whole library:
> a window, taken apart into pixels you write yourself.

## 📊 At a glance

| | |
|---|---|
| **Language** | 100% [Axle](https://axle-lang.dev) — no C, no bindings, no vendored library |
| **Platforms** | Windows (Win32: `kernel32`, `user32`, `gdi32`, `winmm`) and Linux, on X11 (`X11`, `asound`, `c`) or Wayland (`wayland-client`, `asound`, `c`) — one source tree, the target picks the backend and a feature picks between the two Linux ones |
| **Scope** | What a 3D game needs — roughly SDL3 minus gamepads, plus the maths and the renderer SDL leaves to you |
| **Rendering** | Software rasteriser on the CPU — near-plane clipping, back-face culling, depth buffer, perspective-correct interpolation, Blinn-Phong |
| **2-D** | A clipped `Frame` over any surface: rectangles, rounded rectangles, rules, borders, rings, blends, traces — plus two baked anti-aliased faces and a formatter that writes figures as bytes, so a repaint allocates nothing |
| **Idling** | `Events::wait` blocks in the OS until something happens. A program that repaints on change costs no measurable CPU between changes |
| **Failure** | A subsystem that cannot start raises `PlatformError` **from its constructor** — there is no half-built object to test |
| **Teardown** | Every handle-holding class is `Closeable`, so dropping one without `close()` is a compile error (**E0511**), not a leak found later |
| **Portability** | The OS lives under the port directories `axle.toml` declares and nowhere else. Not one `use` in the portable half names a port; `tools/check_seam.sh` holds that, and `axle ports` holds the other half — every seam implemented for every port. A port's implementation is `pub(crate)`: smalt's own files reach it, a program that depends on smalt cannot name it. |
| **Known limits** | Every one of them, with what it would take to lift it: [`LIMITATIONS.md`](LIMITATIONS.md) |
| **`unsafe`** | Only where an OS record is laid out through a typed pointer — `kernel/raw` (the accessors every other site goes through), the platform backends, and `io/bmp`. Nothing above them contains one. |

## ✨ Highlights

- 🪟 **A real window, not a canvas** — `RegisterClassExW` with our own window procedure on Windows, `XCreateSimpleWindow` with `WM_DELETE_WINDOW` on X11, a `wl_surface` given a role by `xdg_toplevel` on Wayland. All three ways a close is a *request* the game may refuse, not an obituary.
- 🧩 **Three backends, one API** — a module path resolves to `platform/<port>/sys_clock.axle`, so a portable file writes `use crate::platform::sys_clock::SysClock;` and never learns which OS it got. Building for another target is `--target`, not a flag day; choosing Wayland over X11 is a feature, because both answer `os = "linux"` and exactly one port may be active.
- 🔌 **A protocol with no library to call it** — `libwayland-client` exports interface *tables* and no request functions: every request is one `wl_proxy_marshal_flags` with an opcode, and an extension's tables are generated per project into C that a pure-Axle library does not have. So smalt builds xdg-shell's three and xdg-decoration's two itself, at startup, out of the same fields the generator emits.
- 🎮 **SDL's event model, kept** — the queue is decoupled from the OS message pump, every event carries the same `kind` / `timestamp` prefix, and scancodes are physical positions, so `Scancode::W` is the key above `Scancode::S` on AZERTY too.
- 📐 **The maths SDL never shipped** — `Vec2` `Vec3` `Vec4` `Mat4` `Quat` `Aabb` `Plane` `Frustum`, all value structs, all tested by a headless example.
- 🖼️ **A 2-D surface, so a program does not have to bring one** — `Surface::frame()` hands back a `Frame`: a clip rectangle and the primitives every overlay is built from. `clipped()` answers a *copy*, so there is no `unclip` to forget and nesting can only narrow. It is also the shape that removes an aliasing hazard: a getter that hands back the colour buffer as an `i32[]` gives it two owners, and the second release is a fault on exit after everything has been drawn.
- 🔤 **Text, without carrying a font** — two faces baked in, 2 bits of coverage per pixel so they are anti-aliased against whatever they land on. `draw` takes a `string` for a label; `drawBytes` takes an address for a figure, because formatting through `string` mints a few hundred allocations a second for text thrown away in the same frame. Three programs built on smalt each wrote this; two ended up with the same six hundred lines of glyph table, already drifting apart.
- 🔢 **Figures straight to bytes** — `Fmt` and `Scratch` write a count, a percentage, a byte size, an elapsed span or a clock into a block you own and answer a length. A repaint allocates nothing at all.
- 😴 **A loop that actually sleeps** — `Events::wait(win, clock, timeoutMs)` blocks in the OS until something arrives. A tool that repaints on change idles at no measurable CPU, instead of choosing between spinning a core and answering input late.
- ⏱️ **Both halves of a frame loop** — `FramePacer` hands out a variable `dt` *and* fixed simulation steps (`steps()` / `alpha()`) drained from the same measurement, so the simulation and the frame cannot drift apart into two timelines.
- 🎨 **A complete software 3D pipeline** — clip, project, cull, half-space fill with a reciprocal depth buffer, perspective-correct attributes, one directional light. No GPU touched, nothing to install.
- 🔊 **Sound with no callback** — every low-latency audio API wants to call *you*, and Axle cannot hand out a function address. `waveOut` opened with `CALLBACK_NULL` reports a finished block as a flag you poll; ALSA's `snd_pcm_avail_update` answers the same question. One three-call cycle, both platforms.
- 🧯 **Failure and teardown are the compiler's business** — constructors raise, `Closeable` is enforced, and `defer` covers the six ways out of `Bmp::read`.
- 🪶 **Nothing to ship** — the produced binary runs on a stock Windows box, or against the `libX11` / `libwayland-client` and `libasound` any Linux desktop already has. No runtime DLL, no redistributable, no vendored library.

## 🚀 Quick start

```toml
# your-game/axle.toml
[package]
name = "your-game"

[dependencies]
smalt = { path = "../smalt" }
```

```rs
use smalt::{Platform, PlatformError, WindowDesc, Events, EventKind, Clock, FramePacer, SoftDevice, Camera, Color};

// `main` is the only place errors stop: everything below propagates with `?`.
fn main() : i32 {
    try {
        return run();
    } catch e : PlatformError {
        println(e.message);
        return 1;
    }
}

fn run() : i32 ! PlatformError {
    // --- Open the platform, and the window on it ---------------------------
    // Every handle here is `Closeable`, so the compiler refuses the path that
    // forgets one. `defer` runs on the way out, including the error way out.
    let platform = new Platform()?;
    defer platform.close();

    let win = platform.open(
        WindowDesc { title: "game", w: 1280, h: 720, resizable: true }
    )?;
    defer win.close();

    // --- The three things a frame is made of -------------------------------
    let clock = new Clock();          // one measurement, shared by pacer and events
    defer clock.close();

    let events = new Events();        // input queue, drained once per frame
    defer events.close();

    let device = new SoftDevice(1280, 720);   // the software 3-D pipeline
    defer device.close();

    let camera = new Camera();

    // --- The loop ----------------------------------------------------------
    let pacer = new FramePacer(60);
    let running = true;
    while (running) {
        // 1. time: `dt` is the variable span since the last tick
        let dt = pacer.tick(clock);

        // 2. input: pump the OS queue, then drain it
        events.pump(win, clock);
        while (events.hasNext()) {
            let e = events.next();
            match e.kind {
                EventKind::Quit => { running = false; }
                _ => {}
            }
        }

        // 3. draw: camera, clear, geometry, present
        //    (`mesh` / `model` / `texture` / `material` are your own assets)
        device.setCamera(camera);
        device.beginFrame(Color::black());
        device.drawMesh(mesh, model, texture, material);
        device.endFrame(win);
    }

    return 0;
}
```

That is the whole setup. No DLL beside the binary, no `[link]` section — `gdi32` and `winmm` are named by the `extern "C" from "…"` blocks that import from them, so a consumer links what it uses without being told twice.

### Prerequisite

Only the Axle compiler, **v0.12.0 or newer**:

```bash
axle --version      # must print 0.12.0 or higher
```

<details>
<summary><b>Missing or older? Install / upgrade Axle →</b></summary>

<br>

- **Windows** — install the x64 `.msi` from the `v0.12.0` (or newer) release; it puts `axle.exe` in `C:\Program Files (x86)\Axle\` and on your `PATH`.
- **Other platforms** — see [axle-lang.dev](https://axle-lang.dev).

On Linux, the X11 port needs `libx11-dev` and `libasound2-dev`; the
Wayland one needs `libwayland-dev` in their place. Both are the `-dev`
package only for the linker's sake — the produced binary runs against
the shared library the desktop already has.

</details>

## 🕹️ Examples

```bash
cd examples/spinning_cube && axle build -O 2 && ./target/spinning_cube.exe
```

A textured cube on a tiled floor, lit and depth-tested, at a locked 60 fps. `WASD` to move, `Tab` to capture the mouse and look around, `Escape` to quit.

**The examples come in three kinds, and the split is the point.**

| Example | What it drives |
|---|---|
| `spinning_cube` | the full 3D pipeline — camera, meshes, textures, lights, the rasteriser |
| `ui_panel` | the 2-D surface — a clipped card, rounded corners, anti-aliased text, a live figure, `Events::wait`, and `F12` to a BMP |
| `donut3d` | **its own** renderer, over `SoftDevice::pixels()` — smalt is only the window |
| `mario3d` | same: a game that already had a renderer and just wanted a framebuffer |
| `hello_window` | the smallest thing that opens and closes cleanly |
| `self_check` | asserts the maths, the frame pacer, the clip, the glyph metrics, the formatters and the containers — runs headless, no display needed |
| `audio_check` | asserts the WAV decode and the device's block cycle |
| `proc_check` | asserts the window procedure — headless, under a second |

A program that already has a renderer should not have to adopt one to get a window. smalt stays a framebuffer underneath, and says so by shipping two programs that use it that way.

`ui_panel --snap` draws one frame, writes `ui_panel.bmp` and quits, so the layout can be checked without anyone standing over the machine at the right moment.

## 🗺️ Coming from SDL

| SDL3 | smalt |
|---|---|
| `SDL_Init` / `SDL_Quit` | `new Platform()` / `platform.close()` |
| `SDL_GetError` | `catch e : PlatformError` → `e.message` |
| `SDL_CreateWindow` | `platform.open(WindowDesc { … })`, or `createWindow(title, w, h, flags)` |
| `SDL_WindowFlags` | `Window::RESIZABLE` and friends, combined with `\|` — or the named fields of `WindowDesc` |
| `SDL_DestroyWindow` | `win.close()` |
| `SDL_PumpEvents` | `events.pump(win, clock)` |
| `SDL_PollEvent` | `events.hasNext()` / `events.next()` |
| `SDL_WaitEventTimeout` | `events.wait(win, clock, timeoutMs)` — blocks in the OS, then pumps |
| `SDL_Event` (a union) | `Event` — one flat struct + `EventKind` |
| `SDL_GetKeyboardState` | `events.isKeyDown(Scancode::W)` |
| `SDL_Scancode` | `Scancode` — same numbering, same meaning |
| `SDL_GetMouseState` | `events.mouseX()` / `mouseY()` / `isButtonDown` |
| `SDL_SetWindowRelativeMouseMode` | `events.setRelativeMouse(true)` |
| `SDL_GetTicks` | `clock.ticks()` |
| `SDL_GetPerformanceCounter` | `clock.counter()` / `clock.frequency()` |
| `SDL_Delay` / `SDL_DelayPrecise` | `clock.delay(ms)` / `clock.delayUntil(us)` |
| *(SDL ships no frame pacer)* | `FramePacer` — `pacer.tick(clock)` sleeps and answers `dt` |
| *(nor a fixed timestep)* | `pacer.steps()` / `pacer.alpha()`, drained from the same measurement |
| `SDL_LoadBMP` | `Bmp::load(path)`; `Bmp::read` raises `IOException` |
| `SDL_SaveBMP` | `Bmp::write(path, frame)` |
| `SDL_LoadFile` | `AssetFile::readAll(path)` |
| `SDL_Rect` | `Rect` |
| `SDL_FillSurfaceRect` | `frame.fillRect(rect, packed)` — and `fillRound`, `border`, `shade`, `ring`, `spark` |
| `SDL_SetClipRect` | `frame.clipped(rect)` — a *copy*, so there is no restore to forget |
| *(SDL ships no font; SDL_ttf is a separate library and a C dependency)* | `BitmapFont::baked(Face::Ui)` — two faces baked in, anti-aliased; `draw` for a label, `drawBytes` for a figure, `fromTables` for a face of your own |
| *(SDL ships no formatter)* | `Fmt` / `Scratch` — figures to bytes, so a repaint allocates nothing |
| *(nor a byte pool or a slot index)* | `BytePool` / `SlotIndex`, both `Closeable` |
| `SDL_GPUDevice` | `SoftDevice`, behind the `RenderDevice` trait |
| `SDL_BeginGPURenderPass` … `SDL_SubmitGPUCommandBuffer` | `beginFrame` … `endFrame` |
| `SDL_PushGPUVertexUniformData` (the MVP) | `setCamera` + a draw's `model` argument |
| *(SDL ships no maths)* | `Vec2` `Vec3` `Vec4` `Mat4` `Quat` `Aabb` `Plane` `Frustum` |
| `SDL_OpenAudioDevice` | `new Mixer()` — opens the default output |
| `SDL_LoadWAV` | `Clip::load(path)`; a bad or missing file is a silent empty clip |
| `SDL_PutAudioStreamData` | `mixer.pump()` — call it far more often than a block lasts |
| *(SDL mixes nothing itself)* | `Mixer` — 32 voices, summed, clamped |
| *(SDL has no 3D audio)* | `playRandPos` + `setListener` — attenuated live, every block |
| *(SDL ships no 3D renderer)* | `Mesh` `Primitives` `Texture` `Camera` `Material` `DirectionalLight` |

**Dropped on purpose:** the multi-platform driver vtable and `bootstrap[]`, `dynapi`, every callback API (`SDL_AddTimer`, `SDL_SetEventFilter`, `SDL_AddEventWatch`) — where SDL calls back, smalt polls — and the 2D `SDL_Renderer`, which has no depth buffer and no 3D transform and so cannot draw a 3D game.

**No `SDL_GetError` equivalent at all.** A failure is raised where it happens and carries its own message, so nothing has to be read back out of a global afterwards.

## 🏛️ Architecture

Layers, bottom to top. **A module never reaches upward.**

```
   ┌───────────────────────────── your game ─────────────────────────────┐
   │            use smalt::{Platform, Window, Events, SoftDevice, …}      │
   └──────────────────────────────┬──────────────────────────────────────┘
                                  │
   ┌──────────────────────────────▼──────────────────────────────────────┐
   │  render/   device (trait) · color · vertex · mesh · texture · camera │
   │            frame (2-D) · glyphs · text · surface                     │
   │            soft/ target · present · raster · shade · device_soft     │
   ├─────────────────────────────────────────────────────────────────────┤
   │  audio/    clip (WAV) · mixer (voices) · bank (variants)             │
   ├─────────────────────────────────────────────────────────────────────┤
   │  math/     vec · mat · quat · geom          io/  file · fmt · bmp    │
   ├─────────────────────────────────────────────────────────────────────┤
   │  video/    window · display · scancode_set1                          │
   │            SEAM  sys_window · sys_drain · sys_cursor                 │
   │            win32/   class · window · proc · keymap · const           │
   │            x11/     x_window_ops · x_decode · x_keymap               │
   │            wayland/ wl_window_ops · wl_win_state · wl_win_events     │
   │                     wl_input                                         │
   │            posix/   evdev_keymap  ← both Linux ports                 │
   ├─────────────────────────────────────────────────────────────────────┤
   │  core/     init · error · timer · event · keyboard · mouse · pump    │
   ├─────────────────────────────────────────────────────────────────────┤
   │  platform/ audio_format                                              │
   │            SEAM  sys_app · sys_clock · sys_screen · sys_blit         │
   │                  sys_audio                                           │
   │            wayland/ wl_drawable · wl_blit_header · wl_screen_probe   │
   │            posix/   sys_clock · blit_scale  ← both Linux ports       │
   ├─────────────────────────────────────────────────────────────────────┤
   │  sys/      dib (the BMP / DIB records — a data format, portable)     │
   │            win32/   win32_types · win32_const · win32_kernel         │
   │                     win32_user · win32_gdi · win32_mm · wide         │
   │                     win32_layout_check                               │
   │            x11/     x11_types · x11_const · x11_lib                  │
   │                     x11_layout_check                                 │
   │            wayland/ wl_lib · wl_libc · wl_request · wl_core          │
   │                     wl_table · wl_args · wl_token · wl_globals       │
   │                     wl_app · xdg_shell · xdg_decoration              │
   │            alsa/    alsa_lib          posix/  posix_time             │
   ├─────────────────────────────────────────────────────────────────────┤
   │  kernel/   raw ← the pointer accessors · blob · mem · store          │
   └─────────────────────────────────────────────────────────────────────┘
```

**How one tree builds for three backends.** There is no `#[cfg]` in Axle,
and there is not one here either. A crate declares its **ports** in
`axle.toml` — one condition, and the directories that carry it:

```toml
[features]
wayland = false

[port.win32]   when = { os = "windows" }                       dirs = ["win32"]
[port.x11]     when = { os = "linux" }                         dirs = ["x11", "posix", "alsa"]
[port.wayland] when = { os = "linux", feature = "wayland" }    dirs = ["wayland", "posix", "alsa"]
```

A module path then resolves to `<path>.axle` when a capability has one
implementation, and to a file in one of the *active* port's directories
when it has one per backend — so a portable file writes

```rs
use crate::platform::sys_clock::SysClock;   // core/timer.axle
```

and gets `platform/win32/`, `platform/x11/` or `platform/wayland/`
depending on the build. The other files are not compiled at all, which is
why a Win32 `extern "C" from "gdi32"` never reaches a Linux link line.

**Exactly one port is active for any target**, which is what keeps the
resolution a lookup rather than a search. `{ os = "linux", feature =
"wayland" }` is *narrower* than `{ os = "linux" }`, so it wins when the
feature is on and X11 answers when it is off; two conditions that
overlapped with neither narrower would be refused rather than settled by
declaration order. Three more shapes are refused rather than guessed: a
path satisfied by *both* a portable file and the active port, two
directories of one port answering the same path, and a seam one port
implements while another does not — the last names the file to write, and
`axle ports` prints the whole table with a tick per seam per port.

One directory can belong to several ports, and `posix/` does: both Linux
ports name it, the Windows one does not, so it is exactly where the two
of them keep what they share.

**X11 or Wayland is chosen when you build, not when you run.** There is
no probe of `$WAYLAND_DISPLAY` at startup and no fallback: the port
system compiles *one* backend, and the other's files are not in the
binary at all. That is the same decision as the seam being a file
boundary rather than a vtable — stated once here because it is the first
thing a Linux user asks.

The default is X11, and deliberately: Xwayland means an X11 binary runs
on every Wayland desktop, while a Wayland binary does not run on an
X11-only session. So the X11 build is the one that runs everywhere, and
the Wayland one is what to build when a session has no Xwayland, or when
X11's own limits are the problem.

Switching is a flag or a line, whichever fits:

```bash
axle build --features wayland          # the root crate
```

```toml
# a game asking the library it uses
smalt = { path = "../smalt", features = ["wayland"] }
```

The flag reaches the root crate; the manifest line is how a dependent
asks, because a feature is declared in one manifest and the edge that
names the crate is the only place that knows which one is meant. Both
only ever *enable* — nothing takes a feature away from a crate that
turned it on.

Choosing at *run time* is a larger question. It would mean both backends
in one binary behind a dispatch — the `RenderDevice` shape applied to the
platform seam — which is what the file boundary was chosen against, and
which only earns its keep if the X11 build's reach through Xwayland ever
stops being enough.

The invariant that makes it hold is one sentence: **the operating system
lives under `src/*/<os>/` and nowhere else, and not one `use` in the
portable half names a platform.** `tools/check_seam.sh` is that sentence
enforced — three rules, each with a `--selftest` that plants the
violation it is for and fails if the check passes on it.

`platform/` sits below `core/` on purpose. A seam that lived beside the
code it serves would be reachable from it, and the first shortcut past it
would go unnoticed; from underneath it can only be called down into. That
is also why `sys_blit` takes a bare `i32[]` rather than a `RenderTarget`,
and why the drawable a window hands the blit lives under `platform/` and
not beside the window that fills it — `x_surface`, the
`(Display *, Window, GC)` triple X11 needs where Win32 has a single
`HDC`, and `wl_drawable`, which holds more than either because Wayland
has no server-side drawable at all.

**The eight seams, and what each costs on each side.**

| Seam | Win32 | X11 | Wayland |
|---|---|---|---|
| `sys_app` | `GetModuleHandleW`, `RegisterClassExW`, `timeBeginPeriod` | `XOpenDisplay` / `XCloseDisplay`, detectable auto-repeat | the token is a *record*: a connection answers nothing until the registry is swept and each global bound |
| `sys_clock` | `QueryPerformanceCounter`, `Sleep` | `clock_gettime(CLOCK_MONOTONIC)`, `nanosleep` — shared with Wayland, in `posix/` | ⟵ the same file |
| `sys_screen` | `GetSystemMetrics` | `XDisplayWidth` / `XDisplayHeight` on a connection of its own | the first `wl_output`'s current mode — one monitor, not the bounding box of all of them |
| `sys_blit` | `StretchDIBits` — the driver scales | `XPutImage` — **no scaling blit**, so a 16.16 nearest-neighbour resample, shared with Wayland in `posix/` | a copy into whichever of **two** shared buffers the compositor is not reading, then attach / damage / commit |
| `sys_audio` | `waveOut` + `CALLBACK_NULL`, four blocks polled for `WHDR_DONE` | `snd_pcm_writei` + `snd_pcm_avail_update`, two staging blocks, `snd_pcm_recover` on an underrun | ⟵ the same ALSA file |
| `sys_window` | `HWND` + `HDC`; the latches are written by our window procedure | `Window` + `GC`; the latches are written by the drain | three objects — `wl_surface`, `xdg_surface`, `xdg_toplevel` — and a handshake: the first commit carries no buffer, it *asks* |
| `sys_drain` | `PeekMessageW` over the thread queue | `XPending` / `XNextEvent` — one stream for input *and* window notices | `poll` on the connection, then `dispatch_pending`; the events arrive as C callbacks that leave records on a ring |
| `sys_cursor` | `ClientToScreen` + `SetCursorPos`; `ShowCursor`'s balanced counter | `XWarpPointer` (window-relative); hiding is a cursor with no pixels | hiding is `set_cursor` with no surface; **there is no warp at all** — see below |

What is deliberately **not** duplicated: the PS/2 set-1 code block
(`video/scancode_set1`), which Windows reads out of `lParam` bits 16..23
and evdev numbered identically for its first eighty-eight keys; the
evdev-to-`Scancode` table above that block (`video/posix/evdev_keymap`),
which X11 reaches by taking its protocol's eight-keycode offset off and
Wayland reaches directly; the nearest-neighbour resample
(`platform/posix/blit_scale`), which neither Linux backend can do while
it blits and Windows never needs; the DIB records (`sys/dib`), a
published data format both a `.bmp` file and `StretchDIBits` carry; and
the PCM format (`platform/audio_format`), which is the seam's contract —
a backend that kept its own copy could open a device at 48 kHz while the
mixer still wrote 44.1, and nothing would fail.

**Objects vs values.** What has identity and a lifetime is a class: `Platform`, `Window`, `Events`, `Clock`, `SoftDevice`, `Mesh`, `Texture`, `Camera`, `RenderTarget`, `Blob`. What is data is a value struct: `Vec3`, `Mat4`, `Quat`, `Color`, `Vertex`, `Material`, `Event`, `Rect`, `Aabb`. Free functions appear only in the raw kernel, where the carrier is context rather than subject.

**Why the rendering seam is a trait and the platform seam is not.** SDL routes every subsystem through a vtable (`SDL_VideoDevice`, `VideoBootStrap`) because a backend is chosen at *run time*. Here it is chosen at compile time, and a vtable would buy nothing but a dispatch on every window operation — so the platform seam is a *file* boundary: one file per capability per OS, each stating its contract in its header, and a port writes the files the compiler names. Rendering is the one place where a second backend is genuinely reachable at run time, so `RenderDevice` is a real trait with `SoftDevice` behind it.

## ⚙️ How it works

### The window procedure

`RegisterClassExW` will not accept a class without an `lpfnWndProc`, and what that field wants is a *C-callable address*. An Axle function value is the fat `{ code, env }` pair — which is what lets a capturing lambda and a bare function share one call shape — and that is not an address `user32` can invoke.

`extern "C" (…) => R` is a thin function pointer: one machine word holding the function's own address, and a named `fn` degrades to it at the boundary. So `video/win32/win_proc.axle` holds a real window procedure, and the messages Windows *sends* arrive as messages:

| what | how |
|---|---|
| the window was closed | `WM_CLOSE`, **recorded not obeyed** — the game decides |
| the window was resized | `WM_SIZE`, with the size Windows sent |
| focus gained or lost | `WM_SETFOCUS` / `WM_KILLFOCUS` |
| minimised or restored | `WM_SIZE` with `SIZE_MINIMIZED` |

Input still comes from the queue, which `PeekMessageW` drains every frame: `WM_KEYDOWN`, `WM_KEYUP`, `WM_CHAR`, `WM_MOUSEMOVE`, the button messages, `WM_MOUSEWHEEL`.

**Where the state lives.** A window procedure captures nothing — it is handed a handle and three integers, and Axle has no mutable globals. The Win32 answer is the window's own user data: a block's address goes in with `SetWindowLongPtrW` at creation and comes back with `GetWindowLongPtrW` on every message. That block is an `extern "C" struct`, because two pieces of code read it at offsets each computes for itself, and it is allocated with `sizeof<WinProcState>()` so a new field cannot leave the allocation behind. `WNDCLASSEXW.lpfnWndProc` is declared as the procedure's own type — `extern "C" (ptr, u32, u64, i64) => i64` — so the class is registered by naming `windowProc`, and a procedure of the wrong shape is a diagnostic at that line instead of a stack the OS unwinds wrongly.

**What the procedure may not do.** Throw. The unwind would cross a frame `user32` owns, which has no landing pad for one — and the compiler refuses a throwing function at the boundary (**E0748**) rather than trusting the author to remember.

**What a close now means.** `DefWindowProcW` answers `WM_CLOSE` by destroying the window; the procedure records it instead. A `Quit` event is therefore a *request* arriving on a window that is still alive, which is what lets a game prompt, save, or refuse.

**Proving it without a user.** `examples/proc_check` calls `Window.selfCheckProc`, which delivers the four sent messages with `SendMessageW` — synchronous, bypassing the queue — and checks what came back. It runs headless, in under a second, and it exercises the whole chain: the class carries our address, the block is reachable from the callback, the procedure writes through the raw pointer, and the event path turns the record into events.

### The Wayland backend

Wayland gives a client less than X11 does, and most of the port is that
sentence made concrete.

**There are no request functions.** `libwayland-client` exports the core
protocol's twenty-four `wl_interface` tables and the proxy machinery, and
nothing else: `wl_surface_commit` and its hundreds of siblings are
`static inline` in the generated headers, each one call to
`wl_proxy_marshal_flags` with an opcode. That call is variadic, so this
port uses its array twin and fills a block of eight-byte slots — which is
what a `union wl_argument` is.

**An extension's tables exist in no library.** They are generated per
project by `wayland-scanner`, into C. So `sys/wayland/xdg_shell` and
`sys/wayland/xdg_decoration` build theirs at startup out of the same
three fields the generator emits — a name, a signature, and the
interfaces each argument names — and the core ones arrive through
`dlsym`, because they are *data* and Axle imports functions. Version 1 on
purpose: the library dispatches an incoming event by using its opcode as
an index into the listener, so an event table shorter than what the
compositor may send reads past the end of a struct.

**A window is three objects and a handshake.** A `wl_surface` is a
rectangle of pixels with no meaning; `xdg_surface` gives it a role's
protocol; `xdg_toplevel` is the role. The first commit carries *no*
buffer — it asks — and the compositor answers with a `configure` the
client must acknowledge before anything it draws is shown.

**Two buffers, because one is a race.** A committed `wl_buffer` belongs
to the compositor until its `release` event says otherwise, so writing
the next frame into the same pages is a tear. `wl_drawable` holds a pair
in one `memfd` pool and writes into whichever is free; a frame that
arrives when neither is gets dropped, which is a frame the compositor was
never going to show.

**A callback cannot reach the queue.** It is C calling us with one
`void *`, and an `EventQueue` is an Axle object with no address to pass.
So the seat's callbacks write records into a ring on the window's state
block, and the drain — Axle code, holding the queue — reads them out.
The same shape the Win32 window procedure needs, reached the other way
round.

**What the protocol refuses, and what smalt does about it.**

| | |
|---|---|
| **No pointer warping** | By design: the compositor owns the input device. A mouse-look game wants `zwp_pointer_constraints_v1` + `zwp_relative_pointer_v1`, which are further extensions with further tables to build. `SysCursor::recentre` does nothing and says so. |
| **No decorations** | A toplevel is the client's pixels, full stop. `xdg-decoration` is asked for where the compositor offers it, and where it does not the window has no frame — that is the desktop's answer, not a failed call. |
| **No window placement, no window position** | Neither can be asked for nor read. |
| **No event injection** | There is no `XSendEvent` here, so `selfCheck` proves the two things a client *can* provoke — a `wl_display.sync` answered into a listener of ours, and the `xdg_surface.configure` that came back through the hand-built table — and claims nothing about the focus edges and the close, which only a person can cause. |
| **No key repeat, no text yet** | A compositor sends no repeats: `repeat_info` asks the *client* to make them. And the character a key produces needs the keymap the compositor sends, which needs `xkbcommon`. Both are additions, not fixes; X11 gets the first from the server and the second from `XLookupString`. |

### The 2-D surface

`render/frame.axle` is the layer three programs built on smalt each wrote for themselves before it existed — a voxel game, a task manager, a network audit. Two of the three ended up with the same six hundred lines of glyph table, re-rasterised, already drifting apart. Four things carry it:

- **A `Frame` is a view, not an owner.** It carries the *address* of a plane somebody else holds, plus the clip in force — four words, no allocation, so `clipped()` is cheap enough to call per widget. That also settles a real crash: a getter handing back the colour buffer as an `i32[]` gives it two owners, and the second release is a fault on exit after everything has been drawn and flushed. There is no array to store, so the mistake is not writable. The price is stated once — **a `Frame` is void after its surface is resized or closed** — and `Surface::frame()` is one call, so taking it at the top of every repaint is both the cheap shape and the correct one.

- **`clipped()` answers a copy.** No `unclip`, nothing to restore on an early return, and nesting can only narrow — a widget handed a clipped frame cannot draw outside what its parent allowed it. That is what makes a list scroll: rows are drawn at their true position, one viewport clips them, and a row crossing the edge is cut mid-pixel rather than appearing whole.

- **The bounds check is per row, not per pixel.** `plot` tests the clip, because a caller plotting one pixel usually cannot say where it lands. The span fillers intersect once and then write a run — four comparisons a row instead of four a pixel — which is why `fillRect` is the call to reach for and `plot` the one to reach for last.

- **Text has two doors, because text has two sources.** `draw` takes a `string`, which is what a label is. `drawBytes` takes an address, which is what a *figure* is: every number on a repainting surface is formatted afresh each frame, and routing those through `string` mints a few hundred allocations a second for text thrown away in the same frame. `io::fmt` writes them as bytes and this draws straight from them, so the repaint path allocates nothing at all.

Glyphs are stored at **2 bits of coverage per pixel**, so text is anti-aliased against whatever it lands on rather than punched out in one colour — at 14 px that is the difference between a UI you read and one you decipher. `drawScaled` multiplies a face by an integer and the coverage survives the multiply, so a scaled heading keeps its edges instead of turning into the staircase a 1-bit font gives you. A game whose pixel font is part of its look keeps it: `BitmapFont::fromTables` takes the same three arrays and hands back every draw method.

### The event loop that sleeps

`Events::wait(win, clock, timeoutMs)` blocks in the OS until something arrives, then pumps. It is one call per port and each one is the platform's own answer: `MsgWaitForMultipleObjects` with `QS_ALLINPUT` on Win32 — the mask covers *sent* messages too, which is where a resize, a focus change and a close arrive; `XPending`, then `XFlush`, then `poll` on `XConnectionNumber` on X11, in that order, because Xlib buffers events in user space and waiting on the socket with events in hand is a program that hangs with its input sitting in memory; and libwayland's prepare/flush/poll/read with the deadline handed to the poll in the middle of it.

Without it a program that repaints on change has to choose between spinning a core and sleeping a fixed period — which answers input that much later and still wakes a hundred times a second to find nothing. Two real tools written on smalt ended their loops with `clock.delay(8)`, and both of their headers say, in as many words, that a tool measuring the machine should not be near the top of its own list.

A frame-driven game should keep calling `pump` and pace with `FramePacer`: waiting for input in a loop that must draw the next frame anyway is a frame that arrives late.

### The rendering pipeline

`render/soft/` is a complete rasteriser: near-plane clipping, perspective divide, viewport transform, back-face culling, half-space triangle fill with a depth buffer, perspective-correct attribute interpolation, and Blinn-Phong shading with one directional light. Three details carry it:

- **Clip before dividing.** A vertex behind the camera has `w <= 0`, and in Axle a division by zero *traps* — it does not produce an infinity. Triangles are clipped against `w >= 0.0001` first, which also stops geometry behind the viewer appearing mirrored in front of it.
- **Interpolate over `w`.** Screen-space linear interpolation of a texture coordinate is wrong for any surface not parallel to the screen. Attributes are carried divided by `w` and divided back by the interpolated `1/w` per fragment — the difference between a correct floor and a 1995 warped one.
- **Depth-test before shading.** A fragment that will lose the depth test must not pay for a texture fetch and a lighting evaluation.

The depth buffer stores **reciprocal** depth and the test is *greater wins*, because only the reciprocal interpolates linearly in screen space.

## 🚧 Not covered

Gamepads, touch, clipboard, dialogs, IME, threads — and macOS. Also, deliberately, **any GPU backend**.

On Wayland specifically: pointer warping, key repeat, text input, cursor
restoration after a hide, and fractional scaling. Each is an addition
rather than a fix, and the [Wayland backend](#the-wayland-backend)
section says which extension or library each one needs.

**The GPU one used to be described here as a limit of the language. That was true and is not any more, and the correction matters because it discouraged the work.** These pages said Axle could not call a function address obtained at run time, which would rule out modern OpenGL, Vulkan, D3D and Metal at a stroke. The C function-pointer cast has since landed — the compiler carries a passing test for the `GetProcAddress` round trip, and smalt already imports `GetProcAddress` — so a GPU backend is work nobody has done rather than work nobody can do. [`LIMITATIONS.md §1.1`](LIMITATIONS.md#11-no-gpu-backend) sets out what each API would actually cost; the short version is that **OpenGL 3.3 Core needs nothing further from the language**, and Vulkan needs only one small thing (no unions, so `VkClearValue` is a hand-laid record) plus a generator for its fifteen hundred declarations.

Threads were described here as blocked for the same reason. They are not: `spawn` and `Task<T>` are the language's, and smalt uses them itself — `mixerLoop` pumps the audio device on a thread of its own, and `Mixer` takes its own lock so a game can play a sound from one thread while another pumps. Everything *else* here — the window, the event queue, the surfaces — still belongs to the thread that created the window, which is what both platforms' event paths require.

Display enumeration covers the primary monitor only — `EnumDisplayMonitors` takes a callback; `EnumDisplayDevicesW` does not and would fit, but is not written.

**Everything smalt does not do is written down in one place: [`LIMITATIONS.md`](LIMITATIONS.md).** It also records what is verified by running it, what is only type-checked on every port, and what is neither.

## 📝 Notes for anyone extending this

Five language rules shape the signatures here:

- **Every member sits on a visibility ladder**, fields and methods alike: unmarked means the declaring class's own, then `pub(derived)`, `pub(file)`, `pub(crate)`, `pub`. smalt writes the narrowest rung that compiles, so the marker is information: `KeyboardState::isDown` is `pub` and `KeyboardState::press` is `pub(crate)`, which says in the signature what the docs used to say in prose — the drain writes the input state and a game reads it. A seam class declares `pub(crate)` and so do its methods; an implementation helper is `pub(file)`.
- **A constant is a `static` field on the class it belongs to.** This used to read the other way round: a `static` field did not cross a crate boundary, so a published constant had to be a `pub const` with the class spelled into its name — `WINDOW_RESIZABLE` rather than `Window::RESIZABLE`. Axle 0.12.1 fixed that, one day after the commit here that wrote the old rule down. So the flags are `Window::RESIZABLE` and friends now, and the prefix is the scope it was imitating. Both forms take a literal, so a constant derived from another is a `static fn` — `AudioFormat::frameBytes()`.
- **A field's default belongs on the field.** `focusedNow : bool = true;` runs at every construction, so a constructor carries only what depends on an argument, and nine classes here have none at all.
- **Storing a parameter into a field or an array element needs `own`** (**E0513** otherwise) when the parameter is a *reference* or a value that owns a resource. A plain value struct — `Vertex`, `Vec3`, `Event` — is copied into the slot and needs no keyword.
- **`mut` on a class parameter is rejected as never-mutated** (**E0281**): calling a mutating method through it is not a mutation *of the binding*.

One shape stays out of reach: **a payload-bearing `enum` cannot carry another payload-bearing `enum`**. It is worth stating precisely, because it is usually read as ruling out more than it does — a variant payload takes a scalar, a **payload-free** `enum`, a `string`, an owning object, a `Shared`/`Weak` handle or a dynamic array. `Scancode` and `MouseButton` are payload-free, so `Event::KeyDown(Scancode, bool)` is writable **today**. `core/event.axle` is a flat struct with a `kind` tag because that is what the two decode tables were written against, not because the language refuses the tagged union.

**Handing a `Closeable` out of a call reads as a transfer.** A getter that returned a field the object still owns — `Window::native()` did — makes the call site an owner with a release to write (**E0511**), because nothing distinguishes it from `AssetFile::readAll`, which really does hand back a fresh block. The field is exposed at `pub(crate)` instead and read as `win.sys`.

Releasing a resource is `defer`'s job wherever a function has more than one way out — `Bmp::read` has six, and one `defer data.close()` covers them all. The compiler enforces the release either way: every `Blob`, `Window`, `Platform`, `Events`, `Clock` and `SoftDevice` implements `Closeable`, so a path that drops one without closing is **E0511**.

## 📄 License

MIT.
