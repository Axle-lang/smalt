# GPU rendering in smalt

smalt draws 3-D on the CPU (`SoftDevice`) and, now, on a GPU through Vulkan. This page is
the design: what a game writes, what is behind it, who owns what, how it is checked, and —
because it is the reason the work was done — how a CPU-rasterised game such as
[voxel-axle](https://github.com/Axle-lang/voxel-axle) moves onto it.

> **Status.** It builds with `axle` 0.14.1 on Windows, `examples/gpu_check` passes,
> `examples/gpu_cube --gpu --smoke` draws, re-uploads, reads a frame back and tears down on a
> discrete GPU through Vulkan (and `--software` on the CPU), and `examples/gpu_shaders` runs a
> program's own mesh, background and pass shaders and checks the frame it reads back.
> voxel-axle draws through it. The Linux ports type-check (`axle check --target
> x86_64-unknown-linux-gnu`, X11 and Wayland) but have not been built or run — see
> [How it is checked](#how-it-is-checked-and-what-is-not).

## The idea

**A game should never see Vulkan.** Not a type, not a name, not a concept it has to hold in
its head. The shape every GPU API converged on — instance, device, queue, command buffer,
descriptor, barrier — is the *driver's* vocabulary, and a game that adopts it has adopted
four thousand lines of someone else's bookkeeping. What a game has is a scene: a camera, a
sun, some lamps, and a list of things (this mesh, this texture, this transform). So that is
the whole API, and the backend is a detail `Renderer` picks.

Three promises follow from that, and each is a design constraint rather than a feature:

| Promise | What it forces |
|---|---|
| **The same program runs without a GPU.** | A software backend behind the *same* contract, and Vulkan loaded at run time, never linked. |
| **A mistake is a missing mesh, not a crash.** | Handles with generations, seeded per renderer; a Vulkan failure is a code the backend acts on (rebuild the swapchain, or report itself lost), never an exception mid-frame; GPU objects are freed only when no frame in flight can name them; a closed renderer refuses everything. |
| **Nothing is shipped.** | No `[link]` section, no SDK, no redistributable: the loader is `dlopen`ed (on Windows, `LoadLibraryExW` of `vulkan-1.dll` by its full System32 path), exactly as the window system is spoken to directly. |

## What a game writes

```rs
let gfx = new Renderer(win, RendererDesc { vsync: true })?;     // GPU if there is one
defer gfx.close();

let cube  = gfx.uploadMesh(builder);                            // MeshBuilder -> handle
let atlas = gfx.uploadTexture(image, SamplerDesc { nearest: true, anisotropy: 8 });

let scene = new Scene(256);
while (running) {
    scene.reset();
    scene.setCamera(camera);
    scene.setSun(DirectionalLight::noon());
    scene.add(cube, atlas, Material::baked(), model);
    scene.addLight(PointLight::make(torch, Color::rgb(1.0, 0.6, 0.3), 8.0));

    let hud = gfx.overlay();                                    // an ordinary `Frame`
    hud.fillRect(Rect::make(8, 8, 220, 32), 0x1F252C);
    font.draw(hud, 16, 28, "hello", 0xE6EAEE);

    gfx.render(scene, win);                                     // one call per frame
}
```

`examples/gpu_cube` is that, complete. The pieces:

| | |
|---|---|
| `Renderer` | The one object. Picks a backend, owns every GPU resource, draws a `Scene`. `Backend::Auto` (default) takes a Vulkan GPU and falls back to the CPU (a software Vulkan device is skipped unless `RendererDesc.softwareVulkan`); `Gpu` refuses to fall back and raises `PlatformError`; `Software` never asks. `backendName()` and `fallbackReason()` say what happened. |
| `Scene` | One frame, *described*: camera, sun, ambient, fog, clear colour, up to eight `PointLight`s, and a list of draws. Reused every frame (`reset()` keeps the storage), so a frame allocates nothing. |
| `MeshBuilder` | Triangles, assembled in the GPU's vertex format (below). `clear()` keeps capacity, so re-meshing a chunk is allocation-free after the first few. |
| `Image` / `SamplerDesc` | RGBA texels with **layers** (a texture array) and how to sample them: nearest or linear, mip chain, anisotropy, repeat or clamp, and `cutout` — the alpha-test threshold a texture is drawn with, so its mip levels keep their coverage. |
| `MeshHandle` / `TextureHandle` | What a program holds in place of a GPU object. Index plus generation: a released handle resolves to nothing, even after its index is reused, and a handle from a renderer that was closed does not resolve in the next one (each numbers its generations from its own seed). |
| `Material` | The existing struct, five fields richer: `opacity`, `cutoff` (alpha test), `directLight` (the sun), `lampLight` (the point lights) and `skyLight`. `Material::baked()` shades from vertex colour alone; `Material::voxel()` reads the vertex colour as baked light with a sky channel (below) and is lit by point lights. |
| `renderer.overlay()` | The 2-D layer: a `Frame` over a CPU buffer composited on top of the 3-D frame, one pixel per pixel from the top-left. A HUD written for `Surface::frame()` runs on it unchanged — except that a word of zero is transparent, so black is drawn as `0x010101`. |
| `ShaderDesc` / `ShaderHandle` | A program's own shading, as SPIR-V: a mesh shader for its draws, a background behind them, passes over the finished frame. See [A program's own shading](#a-programs-own-shading). |
| `updateTexture` | New texels for a texture made without a mip chain, recorded into the next frame without waiting for the GPU — a table a program recomputes every frame. |
| `captureNext` / `captured` | The next frame's pixels, read back: `captured().frame()` is a `Frame` `Bmp::write` takes as it is. On either backend. |

### The vertex

Thirty-two bytes, a contract with `shaders/scene.vert`:

```
byte  0  position  3 x f32        byte 20  normal  4 x snorm8
byte 12  uv        2 x f32        byte 24  colour  4 x unorm8   (r, g, b, a)
                                  byte 28  layer   u32          (0 .. 255)
```

The offsets are named once, on `MeshBuilder` (`POSITION_AT` … `LAYER_AT`); the writer stores
at them and the pipeline's vertex attributes are declared from them. The colour is red first —
not the `0xAARRGGBB` of an `Image` texel nor the `0x00RRGGBB` a `Frame` draws: build it with
`MeshBuilder::rgba` / `rgbaOf`. A vertex is refused (-1) when its position is not a finite number
or its layer is past `MeshBuilder::MAX_LAYER`, the last layer an `Image` holds.

Indices are 32-bit in the builder; a mesh of at most 65 536 vertices is uploaded with 16-bit
ones, half the size (`vk_meshes`).

Two of those fields are what a voxel mesher needs and a model loader does not. The
**colour** is per vertex and multiplies the albedo and the texel — it is where a mesh's
baked light lives. The **layer** picks the tile of a texture array, so a whole world is one
texture and one bind.

## A program's own shading

The built-in shading is a textured mesh lit by a sun, eight lamps and an ambient, fogged. A
program whose look is its own brings its own stages instead (`gpu/shader.axle`), compiled to
SPIR-V and uploaded once — `gfx.uploadShader(ShaderDesc { kind, vert, vertBytes, frag,
fragBytes })` answers a handle, or none on the CPU fallback. A shader is one of three kinds:

| Kind | Stages | Used by | Reads |
|---|---|---|---|
| `Mesh` | vertex and fragment, over the 32-byte vertex | the draws added after `scene.useShader(h)` (until `useShader(ShaderHandle::none())` or `reset`) | set 1 binding 0: the draw's texture |
| `Background` | fragment | `scene.setBackground(h, tex)`: drawn over the whole frame before any draw, with no depth | set 1: its texture |
| `Pass` | fragment | `scene.addPass(h, tex, keep)`: drawn over the whole frame after the draws, in the order added | set 1: its texture; set 2: `shaders/post.glsl` |

Everything around the stages stays smalt's: the vertex format, the pipelines (a mesh shader gets
the same four — opaque or blended, one face or both — chosen by its draw's `Material`), the
targets, the order. A full-screen kind has no vertex stage of its own; smalt's full-screen
triangle feeds it `vUv`, (0, 0) at the top-left.

**What a shader is told** is in `shaders/frame.glsl`, which a program's GLSL includes:

* the frame block `fr` — the view-projection and its inverse (`invViewProj`: a pass turns a
  pixel and its depth back into a world point), the eye, the lights, the target's size, and
  **32 `user` vectors** whose meaning is the program's alone (`scene.setUser(i, Vec4)`);
* the draw's push block `dr` — its model matrix, its material, and **one `user` vector**
  (`scene.setDrawUser(v)`, taken by every draw, background and pass added after it).

A mesh shader also has the two vertex fields the built-in stages leave alone: the normal's
fourth component and bits 8–31 of the layer word (`MeshBuilder::vertexRaw(RawVertex { … })`
writes them; bits 0–7 stay the texture layer).

**A pass** samples what came before it (`shaders/post.glsl`): `prevColor`, what the pass before
drew (the 3-D frame, for the first); `baseColor`, the last pass added with `keep` (or the 3-D
frame); `sceneDepth`, the 3-D frame's depth, 0 at the near plane and 1 at the far one — 1 where
only the background is. A bloom is three of them: an extract, a blur, and a composite that adds
`prevColor` (the blur) to `baseColor` (the frame the extract was kept from).

**The targets.** The 3-D frame is drawn into a colour target of the backend's own (16-bit float
where the device has one), then each pass draws from one target into another, and the last pass —
or a plain copy, when the program added none — draws into the window, with the overlay on top.
Three targets are always enough: a pass reads at most two and never the one it writes. A frame
holds at most `Scene::MAX_PASSES` (12) passes.

**Textures in linear light.** `SamplerDesc.srgb` uploads the texels as sRGB-encoded and averages
the mip chain in linear light, so a shader that lights in linear light samples linear light. The
built-in shading does not ask for it.

`examples/gpu_shaders` is all of it, small: a background, a tinting mesh shader, two passes, and
a frame read back and checked.

## Architecture

```
   your game                                  uses: Renderer Scene MeshBuilder Image Material ...
 ┌──────────────────────────────────────────────────────────────────────────────────────┐
 │ gpu/        renderer · scene · handle · mesh_builder · image · light · shader         │
 │             backend (trait GpuBackend)                                                │
 │   soft/     backend_soft          (the CPU rasteriser, behind the same trait)         │
 │   vk/       vk_backend · vk_overlay · vk_swapchain · vk_pipelines · vk_textures       │
 │             vk_targets · vk_shaders · vk_uploads · vk_readback · vk_meshes            │
 │             vk_heap · vk_mem · vk_graveyard · vk_cmd · vk_context · vk_frame          │
 │             vk_error · spirv · vk_check (the headless test door)                      │
 ├──────────────────────────────────────────────────────────────────────────────────────┤
 │ render/  video/  math/                                                               │
 │   video/<port>/sys_vk_surface    SEAM   a window -> a VkSurfaceKHR                   │
 ├──────────────────────────────────────────────────────────────────────────────────────┤
 │ platform/<port>/sys_gpu_loader   SEAM   find vkGetInstanceProcAddr                   │
 ├──────────────────────────────────────────────────────────────────────────────────────┤
 │ sys/vk/     the Vulkan ABI: constants, records, entry points, layout checks          │
 │ sys/posix/  posix_dl  (dlopen, dlsym — one declaration for both Linux ports)         │
 │ kernel/                                                                              │
 └──────────────────────────────────────────────────────────────────────────────────────┘
```

A module never reaches upward. `gpu/` is the new top layer: it reads `render/` (colours,
`Frame`, the CPU mesh), `video/` (`Window`), `math/`, and `sys/vk`. Nothing below imports it.
Inside it, the portable half (`renderer`, `scene`, `handle`, …) names `vk/` in one place only —
`Renderer` constructs a `VkBackend` — and `GpuCheck`, the public door a headless test uses to
look at the backend's blocks and constants, lives in `vk/` beside what it looks into.

### Why the seams are where they are

The repository's one architectural invariant is that **the operating system lives in the port
directories and nowhere else** (`tools/check_seam.sh`). Vulkan touches the OS in exactly two
places, so there are exactly two new seams, each one file per port:

* **Finding the loader.** `platform/posix/sys_gpu_loader` (X11 and Wayland share it) opens
  `libvulkan.so.1`; `platform/win32/sys_gpu_loader` opens `vulkan-1.dll`. Each yields one
  address, `vkGetInstanceProcAddr`. Everything else is asked of it by name. No library is
  linked, which is what lets a machine with no Vulkan driver build, run and fall back.
* **Making a surface.** `video/{x11,wayland,win32}/sys_vk_surface` turns the window's native
  handles into a `VkSurfaceKHR`. It is the only platform-shaped piece of Vulkan: the swapchain
  and the frame loop above it are identical on all three.

Everything else — `sys/vk` and all of `gpu/` — is portable, and `check_seam.sh` holds it.

### The fact table

Who writes each fact, when, and who reads it. A line with two writers would be a bug; there is
none.

| Fact | Carrier | Single writer | Window | Readers |
|---|---|---|---|---|
| The frame's description (camera, sun, lamps, fog, draws) | `Scene` fields | the program | between `reset()` and `render()` | `Renderer::render`, backends |
| Resolved mesh / texture / shader slot of each draw, background and pass | `DrawItem.meshSlot` / `.texSlot` / `.shaderSlot`, `PassItem` | `Renderer::render` | inside `render()`, before the backend call | the backend |
| A program shader's modules and pipelines | `VkShaders` slot | `VkShaders` (upload / release; a release waits for the device to go idle) | any time, single thread | `VkBackend` when recording |
| New texels for a texture | `VkUploads` queue | `Renderer::updateTexture` (copied to the CPU at once, to the slot's staging buffer once its fence is waited on) | recorded ahead of the next frame's scene pass | that frame's draws |
| A frame read back | `VkReadback` | `captureNext` arms it; the frame's commands copy the window's image; its fence's wait converts it | until the next `captureNext` | `captured()` |
| Draw order (opaque in submission order, then blended far to near) | `Scene.order` | `Scene::prepare`, called by `Renderer::render` | inside `render()` | the backend |
| Which backend slot a handle names | `HandleTable` | `Renderer` (upload / release) | any time, single thread | `Renderer` |
| A mesh's GPU buffers | `VkMeshes` slot | `VkMeshes::create` / `update` | `update` writes a *new* pair and buries the old | `VkBackend::recordDraw` |
| When a GPU object may be destroyed | `VkGraveyard` | `bury…` at release; `sweep` at frame start | `sweep` runs after the slot's fence is waited on | — |
| Device memory ranges | `GpuHeap` free lists | `GpuHeap::alloc` / `release` | single thread | `GpuHeap` |
| The `Frame` and `Draw` shader blocks | mapped uniform / push memory | `VkFrame::writeFrame` / `writeDraw` | before submit | the shaders |
| The 2-D layer's pixels | `Renderer.layer` (a block that only grows; outgrown ones kept until `close()`) | the program, through `overlay()` | cleared on first `overlay()` of a frame | the backend |
| Whether the swapchain is stale | `VkBackend.dirty` | set by `resize`, an out-of-date (or, at a moved size, suboptimal) acquire or present, and `abandon`; cleared only by a build that succeeded | read at the start of `render()` | `VkBackend::render` |
| Whether the GPU is gone | `VkBackend.lost` | `VkBackend::note` (any `VkErr::isFatal` code) and the submit / fence paths | permanent once set | `isLost`, every entry point |
| Where a renderer's handle generations start | `HandleTable` seed | `Renderer`'s constructor (clock mixed with the window) | once | `HandleTable` |

## The CPU fallback, and what it cannot show

`SoftBackend` wraps `SoftDevice` behind the same `GpuBackend` trait. A program written against
`Scene` runs on it unchanged; it does not look the same, and that is stated once so a program
can predict it:

| | GPU | CPU fallback |
|---|---|---|
| Camera, sun, ambient (folded into the material), clear colour | yes | yes |
| The overlay, one pixel per pixel from the top-left, black (zero) transparent | yes | yes |
| Per-vertex colour (baked light) | yes | **dropped** — the CPU `Vertex` has none |
| Point lights (`lampLight`), fog | yes | **absent** — one directional light |
| `opacity`, `cutoff`, texture layers | yes | **ignored** — layer 0 only, always opaque |
| Mip chains, anisotropy, filter choice | yes | **ignored** — nearest |
| `Material::baked()` / `Material::voxel()`, `Scene::setSkyLight` | shades from vertex colour (and the sky colour) | switches the sun off for the draw; the sky colour is ignored — evenly lit |
| `directLight` between 0 and 1 | scales the sun, highlight included | on below 0.5, off above |
| A program's shaders (`uploadShader`) | yes | **none**: the handle is none, a mesh shader's draws take the built-in shading, a background or pass is not drawn |
| `updateTexture`, `captureNext` | yes | yes |

Both shade in the same space: the swapchain and textures are `B8G8R8A8_UNORM` (unless a sampler
asks for `srgb`), so the built-in lighting and mip averaging run on the gamma-encoded values, as
the CPU rasteriser does — the two backends match, and neither is linear-light correct. (A surface that offers no `B8G8R8A8_UNORM` is given
its first format; if that is an sRGB one the picture comes out lighter than the CPU's.)

## The Vulkan backend

**Vulkan 1.0 plus `VK_KHR_surface` / `VK_KHR_swapchain`.** Not 1.3 with dynamic rendering: the
floor every driver, every Vulkan-over-Metal layer and the software rasteriser answers. Nothing
here needs a later feature, so the backend runs where a loader does.

**The bindings** (`src/sys/vk/`) were written from the Khronos registry — about 85 commands and
60 records — with every size and offset measured by a C compiler against the real
`<vulkan/vulkan.h>`. The script that first produced them is not part of this tree; they are
maintained by hand, a command at a time, and `vk_layout_check` holds every record to the measured
numbers: `examples/gpu_check` runs it, and so does `VkContext` before it fills its first record —
a compiler that laid one out differently sends `Auto` to the CPU instead of handing a driver
garbage. Output records the driver fills (properties, capabilities) are not declared as structs
but read at measured offsets (`vk_out`).

**One frame**, with two in flight: wait the slot's fence → sweep the graveyard → acquire an
image, waiting at most a tenth of a second (an out-of-date swapchain is rebuilt and the frame
skipped — that is how a resize is absorbed) → write the frame block, stage the overlay and any
texture updates → record (the uploads; the scene pass: background, opaque then blended draws;
each program pass; the present pass: the last pass or a copy, then the overlay; a read-back when
one was asked for) → submit → present. A steady frame allocates nothing; a swapchain rebuild
(which remakes the targets with it) and an overlay that outgrew its texture (made with room to
spare, so a drag-resize remakes it a handful of times) are the exceptions.

**Failure** has three outcomes, decided by the code and not by where it was met: out of date →
rebuild next frame; no image yet, no area → skip the frame; anything else (`VkErr::isFatal`: a
lost device or surface, a driver out of memory) → the backend is *lost*, `isLost()` says so, and
`render` answers false from then on. That includes a swapchain that cannot be rebuilt and a texture
upload that met a lost device — the cases that used to be a black window forever.

**Memory** is taken from the driver in 64 MiB blocks and sub-allocated (`vk_heap`), because a
driver promises only 4096 allocations and a voxel world has more chunk meshes than that. A request
the driver will not give a 64 MiB block for is retried with a block its own size, and a type it
refused is remembered as full until memory of it is given back. The allocator's invariants — no
overlap, alignment, free neighbours merged, `freeBytes` the sum of the free ranges — are written
at the top of `vk_heap.axle`; nothing in the tree exercises them without a device.

**A resource is never destroyed while a frame can still name it.** `VkGraveyard` buries a
released resource with the number of the frame being built and frees it once the fence of the
slot that could have used it has been waited on. `Renderer::updateMesh` therefore makes a *new*
buffer pair, swaps it in and buries the old — never a write into a buffer the GPU may be
reading.

**Textures** carry their whole mip chain from the CPU: `Image::mipTail` builds each level as the
2 x 2 box of the one above, its colour weighted by alpha (a hole's black does not darken a leaf's
edge) and, with `SamplerDesc.cutout`, its alpha scaled so the share of texels that pass the alpha
test stays what level 0 has; with `SamplerDesc.srgb`, averaged in linear light. One one-shot
submit copies every level of every layer. A texture made without a chain can be rewritten every
frame (`updateTexture`, `vk_uploads`): the copy is recorded into the next frame's own commands,
ahead of its scene pass, and nothing waits.

**Shaders** are GLSL in `shaders/`, committed as SPIR-V (`src/gpu/vk/spirv.axle`), so a consumer
needs no glslang. See [Changing a shader](#changing-a-shader).

**Clip space** is one matrix, once: Camera and `Mat4::perspective` stay OpenGL-convention
everywhere in the library, and `VkFrame::clipFix` (`y' = -y`, `z' = (z + w) / 2`) is applied to
the view-projection when the frame block is written. Counter-clockwise stays the front face.

### Changing a shader

The SPIR-V is not rebuilt by the Axle build. After a shader edit:

1. Run `tools/build_shaders.sh <path to glslang>`. It compiles every module of `shaders/` for
   Vulkan 1.0 and rewrites `src/gpu/vk/spirv.axle` through `tools/spirv_tables.py` — which a
   program uses the same way for its own shaders, with `-I` pointing at smalt's `shaders/` for
   `frame.glsl` and `post.glsl` (`examples/gpu_shaders/build_shaders.sh` is one).
2. If `frame.glsl` changed, read the blocks' offsets back out of a module
   (`spirv-dis scene.frag.spv | grep "OpMemberDecorate.*Offset"`) and make the `FRAME_` / `DRAW_`
   constants in `vk_frame.axle` say the same; `GpuCheck::constants` then checks they still tile.

`examples/gpu_check` checks each module's header and size; that the words are what the GLSL
compiles to is as true as the last run of the script.

## How it is checked, and what is not

All of it is Axle, plus `check_seam.sh`:

| Check | What it holds |
|---|---|
| `axle build` / `axle check` (the examples; Windows, Linux X11, Linux Wayland) | The Axle compiles for every target `axle.toml` promises. |
| `examples/gpu_check` | Run in Axle, headless: the vertex layout byte by byte at the shader's offsets and what a vertex refuses; handles, including empty ones and two tables seeded apart; images, their size clamps and their mip chains (alpha-weighted colour, coverage kept for a cut-out at level 3); draw order — 3 000 blended draws sorted far to near, ties stable — and culling, with and without a camera; every member of both shader blocks at the byte the GLSL gives it, `lampLight`, the inverse view-projection and the `user` vectors included; a raw vertex's program bits; the shader and draw vector a draw takes, and the passes a scene accepts and refuses; `Mat4::inverse` both ways; an sRGB mip level averaged in linear light; the facts written twice agreeing (`GpuCheck::constants`); the Vulkan records' and this port's surface record's layouts; each SPIR-V module's header and size. |
| `examples/gpu_cube --gpu --smoke` / `--software --smoke` | A real device (or the CPU) opens, draws 120 frames with a mesh and a texture released and re-uploaded halfway — while the frames that drew them are in flight — reads one frame back, then the renderer is closed twice and a closed renderer is shown to refuse a frame and an upload. Exit code 0 when all held. |
| `examples/gpu_shaders` | A program's shaders on a real device: a background whose texture is rewritten each frame, a mesh shader, two passes; the frame read back has each one's mark where it should. |
| `gpu_cube --gpu --smoke` under the Khronos validation layer | The same run with `VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation` and `VK_KHRONOS_VALIDATION_VALIDATE_SYNC=1` (core, object-lifetime, thread-safety and synchronization checks): not one error or warning. A run, not a gate — the layer is not part of the tree. |
| `VkContext` at start-up | The record layouts again, on the machine that is about to use them, before any reaches a driver. |
| `check_seam.sh` (`--selftest`) | The OS stays inside the port directories — an `extern "C" from`, a bare `extern "C" fn`, a `native fn` or an `@link` outside a port is refused, and so is a `use` that crosses into another port. |

**Not checked:** that the built-in shading's picture is right (gpu_cube has run on one Windows
discrete GPU; its pixels are read back, not asserted); the program shaders, passes, texture
updates and read-back under the validation layer (gpu_shaders checks their pixels, without it); the sub-allocator under random traffic; that the
embedded SPIR-V is what the GLSL compiles to (see [Changing a shader](#changing-a-shader)); X11
and Wayland surface creation, and any Linux build and run (they type-check); a swapchain rebuilt
under the validation layer (no run resizes the window); a lost device or surface (the paths are
written, not provoked); high-DPI; multiple monitors.

## How voxel-axle uses it

voxel-axle is the test the design was written against: 25 000 lines, an infinite streamed world,
and a CPU rasteriser with greedy meshing, smooth coloured light, ambient occlusion, soft sun
shadows, a one-bounce tint, a ray-marched cloud deck, fog toward the sky, bloom, god-rays and an
underwater haze. It now draws through `Renderer` when there is a GPU, and keeps its own
rasteriser when there is not; its `engine/render/gpu` is the whole port. What each piece became:

| voxel-axle | On `Renderer` |
|---|---|
| Chunk faces in `FaceMesh`, lit per corner per frame | Each chunk meshed into two `MeshBuilder`s (one-sided; water and partial tops two-sided) when its mesh or its light changes. A corner carries what it read of the light volumes — the light levels and occlusion in the layer word's program bits, the sun's visibility in `normal.w`, the bounce and sky access in the colour — and a `Mesh` shader does the per-frame arithmetic, the CPU's line for line. |
| The day | Thirty `user` vectors a frame: the sun, its tint, the sky's colours, the light model's constants. Day turns to night with no re-mesh. |
| World coordinates hundreds of thousands of blocks out | A render origin at the eye's chunk; chunk meshes are chunk-local and placed by whole blocks. |
| Sky, sun, moon, cloud deck | A `Background` shader; the deck is a texture rewritten each frame (`updateTexture`). |
| Fog toward the sky behind each surface, god-rays, underwater, bloom | `Pass` shaders reading `sceneDepth` and `invViewProj`; the bloom is an extract, a blur and a composite, with `keep`. |
| Mobs, torches, the selection outline | One mesh rebuilt each frame. |
| HUD and pause menu | `overlay()`, unchanged; the menu's veil is a pass, since the overlay cannot darken what is under it. |
| `--snap` | `captureNext` / `captured`. |

A pinned capture on each backend, side by side, is how the two are compared: 95–99 % of the
pixels within four levels of each other.

## Limits and next steps

* **Linux type-checks but has not been built or run** — see the status note at the top.
* **A program's shaders are SPIR-V it compiles itself** (`tools/spirv_tables.py`); the CPU
  fallback cannot run them. A pass reads two colour targets and the depth, no more.
* **No shadow maps, no MSAA, no instancing.** A program draws shadows the way voxel does — baked
  into its vertices — or not at all.
* **Meshes are host-visible**, written by `memcpy`. A discrete GPU reads them across the bus (the
  heap prefers device-local host-visible memory where it exists). A staged upload to device-only
  memory is the next step for large static scenes.
* **A texture's first upload is synchronous** (a one-shot submit and a wait), and so is a mip
  chain's; only a texture without one can be rewritten every frame (`updateTexture`).
* **Eight point lights**, per-pixel, no shadows.
* **The device name is not shown** — only its kind (discrete, integrated, software) — because
  turning a C string into an Axle `string` has no precedent in the library yet.
* **Wayland**: the window already carries a shared-memory buffer from its CPU blit; a program must
  present through one path only. `Renderer` does; `Window::show` on Wayland attaches the CPU's
  buffer again, so it belongs to the CPU path.
* **A renderer belongs to the window it was made on.** `render` takes the window again (the
  program owns it) and refuses any other one.
* **A lost device is permanent**: `render` answers false from then on, and `Renderer::isLost()`
  says so — the program drops the renderer and makes a `Backend::Software` one (`gpu_cube` shows
  how). Handles from the old renderer resolve to nothing in the new one; re-upload.
* **Blended draws are sorted per draw, not per triangle**, by the box centre (bounded draws) or
  the model's origin: two intersecting translucent meshes can sort wrong.
* Everything the CPU renderer's own list in `LIMITATIONS.md §1.8` says still holds for the fallback.
