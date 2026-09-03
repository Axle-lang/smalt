# Limitations

What smalt does not do, what Axle does not let it do, and — for each —
whether it is a decision, a gap, or something waiting on the compiler.

Three sections, because the three have different answers:

- [**The library's own scope**](#1-the-librarys-own-scope) — what is
  deliberately not here.
- [**What the language costs**](#2-what-the-language-costs) — shapes that
  are awkward, or impossible, in Axle today. **Every one has been run
  against the compiler.** Three entries in the first draft of this file
  were taken from prose instead, and all three were wrong; they now say
  what actually happens, and say that they used to say otherwise.
- [**What is verified, and how far**](#3-what-is-verified-and-how-far) —
  which claims are tested, which are type-checked only, and which are
  neither.

A line marked **★** is one where the limitation has a workaround that is
already in the source; follow the reference and you will find it.

---

## 1. The library's own scope

### 1.1 No GPU backend

Nothing here touches a graphics driver. Everything is rasterised on the
CPU.

**The reason usually given for this is now wrong and is worth correcting,
because it discouraged the work.** smalt's own comments said, in five
places, that Axle could not call a function address obtained at run
time — which would rule out modern OpenGL, Vulkan, D3D and Metal, since
all of them are reached through addresses a loader hands back. That has
not been true since the C function-pointer cast landed:

```axle
unsafe {
    let draw : extern "C" (u32, i32, i32) => void =
        GetProcAddress(gl, name) as extern "C" (u32, i32, i32) => void;
    draw(0, 0, 0);
}
```

The compiler carries a passing test for exactly this shape
(`tests/samples/compile_pass/ffi/c_function_pointer_round_trip.axle`),
and smalt already imports `GetProcAddress`
(`src/sys/win32/win32_kernel.axle`). So a GPU backend is **work that has
not been done**, not work that cannot be.

What it would actually cost, in the order the costs bite:

| | |
|---|---|
| **OpenGL 3.3 Core** | The cheapest by a wide margin. ~350 entry points behind `wglGetProcAddress` / `glXGetProcAddress`, no creation structs, no unions, every argument a scalar. Nothing below blocks it. `RenderDevice` (`src/render/device.axle`) is already the seam it would implement. |
| **Vulkan 1.0** | More tractable than it first looks. Creation records are ordinary `extern "C" struct` literals passed with `&` (§2.9), and arrays of them likewise, so the bulk of a binding is mechanical. What is left is §2.10 (no unions — `VkClearValue` needs a hand-laid record) and the sheer count: ~1500 functions and structs, which wants a `vk.xml` generator rather than a person. |
| **Direct3D 12** | Reachable — a COM vtable slot is pointer arithmetic and a cast — but ~100 slots per interface, by hand, with nothing checking them. This is the argument for *not* targeting it. |
| **WebGPU (`wgpu-native`)** | Closest to "the universal API", and the same shape as Vulkan but far smaller. Its cost is not the language at all: it reintroduces a shared library to ship, which is the one thing this library is built not to need. |

Shader compilation is not a blocker either way: SPIR-V can be embedded as
bytes, and GLSL and WGSL are text.

### 1.2 Platforms

Windows (Win32) and Linux (X11, or Wayland behind a feature). **No
macOS.** Cocoa is Objective-C, reached through `objc_msgSend` with
selectors — possible through the same FFI, and not written.

### 1.3 Input and desktop integration

No gamepads, no touch, no clipboard, no file dialogs, no IME, no
drag-and-drop, no multi-window input routing. Display enumeration covers
the **primary monitor only** (`src/video/display.axle` says which calls
the rest would need).

### 1.4 Wayland, specifically

The Wayland port is real but thinner than the X11 one, and each gap is an
extension rather than a bug:

| Missing | Needs |
|---|---|
| Pointer warping (so relative mouse-look does not run out of screen) | `zwp_pointer_constraints_v1` + `zwp_relative_pointer_v1` |
| Key repeat | The client synthesising it from `repeat_info` |
| Text input (`EventKind::TextInput`) | `xkbcommon` for the keymap |
| Cursor restoration after a hide | A `wl_cursor` theme |
| Fractional scaling | `wp_fractional_scale_v1` |
| Window placement, window position | Nothing — the protocol refuses both by design |

`SysCursor::recentre` does nothing on Wayland and says so.

### 1.5 Text

`BitmapFont` is **bitmap** text and nothing more.

- **Two baked faces** — a 14 px UI face and a 22 px headline face, both
  through `BitmapFont::baked(Face::…)`. `BitmapFont::fromTables` takes
  your own arrays, so a game whose pixel font is part of its look keeps
  it and still gets every draw method. What there is no such thing as
  here is a font **loader**: a TrueType rasteriser is a different
  project.
- **The headline face carries a subset of ASCII** — digits, `.`, `,`,
  `%`, `/` and the unit letters a figure uses. It is for figures. A word
  handed to it silently loses the letters it does not have. Use
  `Face::Ui` for prose. ★ `examples/ui_panel` shows the split.
- **ASCII only.** Codes above 127 draw nothing. There is no shaping, no
  kerning, no bidirectional text, no combining marks.
- **Scaling is an integer multiple** (`drawScaled`). There is no hinting
  and no sub-pixel positioning.

### 1.6 Images

`Bmp` reads and writes **uncompressed BMP** — 24- and 32-bit in, 24-bit
out. No PNG (an inflate implementation), no JPEG (a DCT). A file that
cannot be decoded yields the magenta checker rather than an error, on
purpose.

### 1.7 Audio

- 32 simultaneous voices, fixed. A 33rd steals the least useful.
- Everything is normalised at load to **mono 16-bit** at the device rate.
  A stereo file is downmixed by averaging; a positional source has no
  stereo to preserve anyway.
- Resampling is **nearest-neighbour**. Audible on music or speech;
  inaudible on the short noisy clips a game plays.
- WAV only, PCM only, 16-bit only. Any other file is silence, not an
  error.
- No effects, no filters, no reverb, no per-voice pitch.
- The distance curve is **linear to zero at `range`**, not inverse-square:
  physics never reaches zero, and a game needs a distance past which a
  sound is gone.

### 1.8 The software renderer

`SoftDevice` is a complete pipeline, not a fast one. One directional
light, no shadows, no transparency sorting, no mipmaps, no anisotropy,
no multi-threading of the raster. A non-uniform scale is transformed
wrongly (the normal matrix would need the inverse transpose, which
nothing here produces).

**The library's own 3-D layer has no user.** Three programs built on
smalt — a voxel game, a task manager, a network audit — all take the
window, the event queue, the clock and the pixels, and none of them uses
`Mesh`, `Camera`, `Material` or `drawMesh`. Treat `render/soft/` as a
worked example rather than as the renderer you are meant to grow into.

### 1.9 The containers in `kernel::store`

Deliberately not general-purpose. `std::collections` has those.

- `BytePool` is **append-only and never compacted**. `reset` forgets
  everything at once, which is safe only when whatever held the offsets is
  rebuilt with it. Correct for stable identities (a path, an address, a
  name); wrong for a set that churns.
- `SlotIndex` **never resizes and has no `remove`**. Removal under linear
  probing needs tombstones; `clear` and rebuild is the shape it is for.
  Build it at twice the entries you will insert — a full table drops the
  insert and answers `false`.

### 1.10 `Frame` lifetime

A `Frame` carries the **address** of a plane somebody else owns. It is
void after that surface is resized or closed. Take it again:
`Surface::frame` is one call and no allocation, so taking it at the top
of every repaint is both the cheap shape and the correct one.

This is the one hazard the type removes rather than adds: the shape it
replaces — a getter handing back the colour buffer as an `i32[]` — gives
the buffer two owners, and the second release is a fault on exit after
everything has been drawn.

**Those getters are still there**, and saying otherwise would be the
comfortable half of the truth. `Surface::pixels`, `RenderTarget::pixels`
and `SoftDevice::pixels` remain, because a program with a renderer of its
own wants the array and not a drawing API — `examples/donut3d` and
`examples/mario3d` are exactly that. The rule is unchanged and is now
written on each of them: **passing what they return is safe; storing it
in a field is the double free.** `frame()` is the door for everything
else, and cannot be that mistake.

### 1.11 Threading

`Mixer` takes its own lock and is safe to `play` from one thread while
`mixerLoop` pumps it from another. **Nothing else here is.** A `Window`,
an `Events`, a `Surface`, a `SoftDevice` belong to one thread — the one
that created the window — and the OS event path on both platforms
requires it.

`close()` ordering is still yours: stop the pump, join the task, *then*
close the mixer.

---

## 2. What the language costs

Every item here has been **run against the compiler**, not read off the
documentation. Three entries in the first draft of this file were taken
from prose — one from another program's comment — and all three were
wrong; §2.7, §2.8 and §2.9 now say what actually happens, and say that
they used to say otherwise. The probes are throwaway single-file programs;
none is checked in, because what is worth keeping is the answer.

### 2.1 A method must be declared before it is used, inside a `struct`

A `struct` method calling a sibling declared **later in the same body**
is rejected — and the diagnostic names neither the cause nor the method:

```axle
pub struct Frame {
    pub fn fill(self, packed : i32) : void {
        self.fillRect(self.clipRect(), packed);   // E0006: expected 0, found 3
    }
    pub fn fillRect(self, r : Rect, packed : i32) : void { … }
}
```

Order the body so a method sits below what it calls. ★ `src/render/frame.axle`
puts `fillRect` above `fill` for exactly this reason.

Classes were fixed for this in 0.12.1 ("a method resolves wherever its
class is declared"); structs appear not to have been.

### 2.2 A struct literal cannot be empty

Every field of `Mat4` has a default, and `Mat4 { }` is still a parse
error. One field has to be named:

```axle
return Mat4 { m00: 1.0 };   // ★ src/math/mat.axle — `identity()`
```

### 2.3 Some ordinary names are reserved

`free(arr)` is a built-in and `of` is the `for … of` keyword, so neither
can name a method. Both were found the same way — by writing the obvious
name and reading a parse error that points at the name rather than
saying it is taken:

| Wanted | Is | Named instead |
|---|---|---|
| `BytePool::free()` | the deallocator | `BytePool::spare()` |
| `BitmapFont::of(face)` | `for (x **of** xs)` | `BitmapFont::baked(face)` |

### 2.4 No operator overloading

`a.plus(b)`, not `a + b`, for every value type in `math/`. More verbose
to write; unambiguous to read. It is also why `Color` has both a struct
form and a set of packed-integer statics rather than one type that could
be used arithmetically in both.

### 2.5 No custom iteration

`for (x of thing)` accepts a range or an array and nothing else (E0517).
A container cannot be made iterable, which is why the event loop is:

```axle
while (events.hasNext()) { let e = events.next(); … }
```

and not `for (e of events)`.

### 2.6 No default parameter values, and one constructor per class

Which is why the ergonomic shape is an **options record with field
defaults** rather than overloads:

```axle
platform.open(WindowDesc { title: "game", w: 1280, h: 720, resizable: true })
```

A struct field default must be a **constant** (E0760) — a literal, an
operator over literals, a `::` path, or a literal of another struct built
from those. A class field's default runs in the constructor and keeps the
freedom.

★ "One constructor" is the sharper half. A class that can be built two
ways has to pick which one the constructor is and make the other a
factory — and the right pick is the **primitive** one, or the factory
ends up passing arguments the other path ignores. `BitmapFont` takes
tables in its constructor; `BitmapFont::baked(Face::Ui)` and
`BitmapFont::fromTables(…)` are the two doors. The first draft had it the
other way round and every call site grew three arguments it did not
mean.

### 2.7 `@derive` on a `struct` is accepted and synthesises nothing

This one is worse than being unsupported, which is why it is worth
stating precisely. `@derive(Eq)` on a `struct` **compiles**:

```axle
@derive(Eq)
struct P { x : i32; y : i32; }
```

and the method is not there — the call is `E0015: method equals not found
on type P`, at the call site, with nothing pointing back at the
annotation that promised it. On a class it works.

`@derive` is also not available on a generic class. So `Vec3`, `Mat4`,
`Rect` and every other value type here have hand-written comparisons or
none.

### 2.8 A `Task<T>` in a field — what is actually true

A `Task<i32>` field, spawned in a constructor and joined in a method,
**compiles and runs**, as long as the same thread does both. An earlier
draft of this file said it could not be done; that was taken from a
comment in another program rather than from the compiler, and it is
wrong.

What the shape does cost is where the *join* has to happen: the handle is
minted on one thread and consumed on one thread, so an object holding one
has to be reached by that thread and by no other, which an object is
exactly the wrong shape for advertising.

★ So `mixerLoop` is still a free function and `Mixer` still has
`requestStop` / `isRunning` — but as a **choice**, not a workaround. The
three lines say who stops the pump, who waits for it, and who releases
the device, in that order, which is an order a `Mixer::startPump()`
hiding the handle could not have made visible:

```axle
let audio : Task<i32> = spawn mixerLoop(mixer);
…
mixer.requestStop();
audio.join();
mixer.close();
```

### 2.9 Address-of a local aggregate — this works

An earlier draft of this file said it did not, and named it as the one
thing standing between Axle and a readable Vulkan binding. That was read
off the FFI chapter, which only demonstrates `&arr[0]`, instead of being
asked of the compiler. Both of these run:

```axle
extern "C" struct QueueInfo { pub family : i32; pub count : i32; }

let one : QueueInfo = QueueInfo { family: 11, count: 13 };
unsafe { cmemcpy((&copy) as ptr, (&one) as ptr, sizeof<QueueInfo>()); }

let infos : QueueInfo[2];              // and an array of them,
unsafe { vkThing((&infos[0]) as ptr, 2); }   // handed over as one pointer
```

So the shape Vulkan is built out of — a creation record filled as a
literal and passed by pointer, and an array of them passed as one — is
**writable directly**, with no `Blob` and no field-by-field fill.

`Blob` is still what this library uses for OS records, and still for a
reason: a `MSG` or a `WNDCLASSEXW` has to keep an address the OS reads
*after* the call that took it, which is a lifetime guarantee, not an
addressing one.

### 2.10 No unions

`VkClearValue` is a union of unions. Workable as a `@packed extern "C"
struct` of the right width with the offsets computed by hand — which is
exactly the class of error `@packed` plus `offsetof` exists to eliminate
everywhere else.

### 2.11 A payload-bearing `enum` cannot carry another one

A variant payload takes a scalar, a **payload-free** enum, a `string`, an
owning object, a `Shared`/`Weak` handle or a dynamic array.

Worth stating precisely, because it is often read as ruling out more than
it does: `Scancode` and `MouseButton` are payload-free, so
`Event::KeyDown(Scancode, bool)` is writable today. `core::event` is a
flat struct with a `kind` tag because that is what the two decode tables
were written against, not because the language refuses the tagged union.

### 2.12 A top-level initialiser must be a literal

E0720. A baked table is therefore a function returning an array, called
once and held — ★ `src/render/glyphs.axle`.

### 2.13 The arithmetic guard rails

Each of these is a deliberate language decision that shapes code here:

- **Division by zero traps.** It does not produce an infinity. Every
  constructor in `math/` that divides guards its divisor first, and
  `Vec3::normalized` answers the zero vector rather than dividing by a
  zero length.
- **Float → int needs a named rounding.** `as` is rejected; write
  `.round()`, `.floorToInt()`, `.truncToInt()` or `.ceilToInt()`.
- **Signed and unsigned do not mix**, and `-x` on an unsigned value is an
  error. Hence `Mem::udwordAt` beside `Mem::dwordAt`: the two readings of
  the same 32 bits are separate calls rather than a cast the caller has to
  remember.

### 2.14 One `extern "C"` declaration per symbol per program

Two declarations of one libc symbol in a compilation unit are two
distinct declarations of the same name, and the linker is handed
`malloc.1`. ★ `poll` and `PollFd` are declared once in the X11 port
(`sys/x11/x11_lib.axle`) and once in the Wayland port
(`sys/wayland/wl_libc.axle`), and never both — only one port is active in
a build.

### 2.15 An array literal does not coerce in argument position

A `[…]` literal is a **fixed** `i32[N]`. It becomes a dynamic `i32[]`
through a `let` with the type written, or through a `return` — and not
through being passed:

```axle
fn takes(t : i32[]) : void { }

takes([1, 2, 3]);                    // E0001: expected i32[], found i32[3]
let t : i32[] = [1, 2, 3];
takes(t);                            // ✓
```

★ It is why `render::glyphs` publishes its tables as functions returning
`i32[]` rather than as values, and why `self_check` binds a custom face's
tables before handing them to `fromTables`.

### 2.16 A `static` field must be a literal, not a named constant

```axle
const FIGURE_BYTES : i32 = 32;
class Scratch {
    pub(file) static HEADROOM : i32 = FIGURE_BYTES;   // E0720
}
```

The diagnostic asks for "a literal (optionally negated)". So a constant
derived from another is either a module-level `const` used directly, or a
`static fn` — `AudioFormat::frameBytes()` is the second shape, and
`io::fmt` takes the first after this rule was hit while fixing a bound.

---

## 3. What is verified, and how far

### 3.1 Verified by running it

`examples/self_check` is headless and exits with the failure count. It
covers the maths (quaternion against matrix, frustum, AABB, degenerate
inputs), the frame pacer against the wall clock, and — since the 2-D
surface landed — the clip nesting and the fact that it can only narrow,
the span fillers' exclusive far edge, the blend midpoint, `disc`, a
partly-clipped `blit` taking the right source column, `spark` on a flat
run, the packed colour statics, glyph rendering and metrics, the headline
face's subset, a face built from a caller's own tables, `drawScaled` at
×2, all nine formatters, a `literal` truncated rather than run past the
end of its block, the byte pool, the slot index including its zero-key
sentinel, the fixed-timestep accumulator including its catch-up ceiling,
and the UTF-8 to UTF-16 transcode including a surrogate pair.

**Every assertion added there has been negative-controlled** — broken on
purpose once, to check it fails — because a test that cannot fail is
worse than no test: it reports coverage it does not have.

`examples/ui_panel --snap` draws one frame and writes it to a BMP.
`examples/audio_check` and `examples/proc_check` exercise the device and
the window procedure.

### 3.2 Type-checked on every port, run on one

`axle check --target …` and `axle ports` verify all three ports from any
machine, and both are clean. **They are only run on Windows here.**

The one addition where that gap matters is `Events::wait`:

| Port | Mechanism | State |
|---|---|---|
| Win32 | `MsgWaitForMultipleObjects` with `QS_ALLINPUT` | type-checked **and run** |
| X11 | `XPending`, then `XFlush`, then `poll` on `XConnectionNumber` | **type-checked only** |
| Wayland | libwayland's prepare/flush/poll/read with a deadline | **type-checked only** |

The X11 and Wayland implementations follow the sequence each library
documents, and the Wayland one is the existing non-blocking read with the
timeout threaded through rather than a second copy of the ordering rules.
Neither has been observed waking on a real event.

### 3.3 Held by a tool rather than by a test

- `tools/check_seam.sh` — no `use` in the portable half names a port
  directory.
- `axle ports` — every seam is implemented for every promised target,
  with the same surface. It is what caught `waitReady` existing on Win32
  and nowhere else, at the moment it was added.
- `Bmp::verifyLayout()` and the two `*_layout_check` files — the OS
  records this build fills are the ones the OS reads.

### 3.4 Not verified

- Long-running behaviour. Nothing here has been left up for hours.
- Multi-monitor, high-DPI, and display hot-plug.
- Wayland against more than one compositor.
- `BytePool` and `SlotIndex` at their capacity limits under real load —
  the refusal paths are tested, the pressure is not.
- Memory over a long session. There is no leak check beyond the
  compiler's own `Closeable` enforcement and `--alloc-stats`.
