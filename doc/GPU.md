# GPU rendering in smalt

smalt draws 3-D on the CPU (`SoftDevice`) and, now, on a GPU through Vulkan. This page is
the design: what a game writes, what is behind it, who owns what, how it is checked, and —
because it is the reason the work was done — how a CPU-rasterised game such as
[voxel-axle](https://github.com/Axle-lang/voxel-axle) moves onto it.

> **Status.** It builds with `axle` 0.14.1 on Windows, `examples/gpu_check` passes, and
> `examples/gpu_cube --gpu --smoke` draws, re-uploads and tears down on a discrete GPU through
> Vulkan (and `--software` on the CPU). Nothing asserts the pixels a driver draws, and the
> Linux ports type-check (`axle check --target x86_64-unknown-linux-gnu`, X11 and Wayland) but
> have not been built or run — see
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

Two of those fields are what a voxel mesher needs and a model loader does not. The
**colour** is per vertex and multiplies the albedo and the texel — it is where a mesh's
baked light lives. The **layer** picks the tile of a texture array, so a whole world is one
texture and one bind.

## Architecture

```
   your game                                  uses: Renderer Scene MeshBuilder Image Material ...
 ┌──────────────────────────────────────────────────────────────────────────────────────┐
 │ gpu/        renderer · scene · handle · mesh_builder · image · light · backend        │
 │             trait GpuBackend                                                          │
 │   soft/     backend_soft          (the CPU rasteriser, behind the same trait)         │
 │   vk/       vk_backend · vk_overlay · vk_swapchain · vk_pipelines · vk_textures       │
 │             vk_meshes · vk_heap · vk_mem · vk_graveyard · vk_cmd · vk_context         │
 │             vk_frame · vk_error · spirv · vk_check (the headless test door)           │
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
| Resolved mesh / texture slot of each draw | `DrawItem.meshSlot` / `.texSlot` | `Renderer::render` | inside `render()`, before the backend call | the backend |
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

Both shade in the same space: the swapchain and textures are `B8G8R8A8_UNORM`, so lighting and
mip averaging run on the gamma-encoded values, as the CPU rasteriser does — the two backends
match, and neither is linear-light correct. (A surface that offers no `B8G8R8A8_UNORM` is given
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
skipped — that is how a resize is absorbed) → write the frame block, stage the overlay → record
(overlay upload, render pass, opaque then blended draws, overlay) → submit → present. A steady
frame allocates nothing; a swapchain rebuild and an overlay that outgrew its texture (made with
room to spare, so a drag-resize remakes it a handful of times) are the exceptions.

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
test stays what level 0 has. One one-shot submit copies every level of every layer.

**Shaders** are GLSL in `shaders/`, committed as SPIR-V (`src/gpu/vk/spirv.axle`), so a consumer
needs no glslang. See [Changing a shader](#changing-a-shader).

**Clip space** is one matrix, once: Camera and `Mat4::perspective` stay OpenGL-convention
everywhere in the library, and `VkFrame::clipFix` (`y' = -y`, `z' = (z + w) / 2`) is applied to
the view-projection when the frame block is written. Counter-clockwise stays the front face.

### Changing a shader

The SPIR-V is not rebuilt by the Axle build, so a shader edit is three steps, by hand:

1. Compile and validate each changed module:
   `glslangValidator -V --target-env vulkan1.0 --spirv-val -I shaders shaders/scene.frag -o scene.frag.spv`.
2. Replace its table in `src/gpu/vk/spirv.axle` with the module's words — eight to a line, as
   signed decimals — and its `*Bytes()` with the module's size.
3. If `frame.glsl` changed, read the blocks' offsets back out of the module
   (`spirv-dis scene.frag.spv | grep "OpMemberDecorate.*Offset"`) and make the `FRAME_` / `DRAW_`
   constants in `vk_frame.axle` say the same; `GpuCheck::constants` then checks they still tile.

`examples/gpu_check` checks each module's header and size; that the words are what the GLSL
compiles to is only as true as step 2 was done.

## How it is checked, and what is not

All of it is Axle, plus `check_seam.sh`:

| Check | What it holds |
|---|---|
| `axle build` / `axle check` (both examples; Windows, Linux X11, Linux Wayland) | The Axle compiles for every target `axle.toml` promises. |
| `examples/gpu_check` | Run in Axle, headless: the vertex layout byte by byte at the shader's offsets and what a vertex refuses; handles, including empty ones and two tables seeded apart; images, their size clamps and their mip chains (alpha-weighted colour, coverage kept for a cut-out at level 3); draw order — 3 000 blended draws sorted far to near, ties stable — and culling, with and without a camera; every member of both shader blocks at the byte the GLSL gives it, `lampLight` included; the facts written twice agreeing (`GpuCheck::constants`); the Vulkan records' and this port's surface record's layouts; each SPIR-V module's header and size. |
| `examples/gpu_cube --gpu --smoke` / `--software --smoke` | A real device (or the CPU) opens, draws 120 frames with a mesh and a texture released and re-uploaded halfway — while the frames that drew them are in flight — then the renderer is closed twice and a closed renderer is shown to refuse a frame and an upload. Exit code 0 when all held. Pixels are not asserted. |
| `gpu_cube --gpu --smoke` under the Khronos validation layer | The same run with `VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation` and `VK_KHRONOS_VALIDATION_VALIDATE_SYNC=1` (core, object-lifetime, thread-safety and synchronization checks): not one error or warning. A run, not a gate — the layer is not part of the tree. |
| `VkContext` at start-up | The record layouts again, on the machine that is about to use them, before any reaches a driver. |
| `check_seam.sh` (`--selftest`) | The OS stays inside the port directories — an `extern "C" from`, a bare `extern "C" fn`, a `native fn` or an `@link` outside a port is refused, and so is a `use` that crosses into another port. |

**Not checked:** that the picture a real driver draws is right (gpu_cube has run on one Windows
discrete GPU; nothing asserts its pixels); the sub-allocator under random traffic; that the
embedded SPIR-V is what the GLSL compiles to (see [Changing a shader](#changing-a-shader)); X11
and Wayland surface creation, and any Linux build and run (they type-check); a swapchain rebuilt
under the validation layer (no run resizes the window); a lost device or surface (the paths are
written, not provoked); high-DPI; multiple monitors.

## Porting voxel-axle

voxel-axle is a good test of the design because it is the opposite of a toy: 25 000 lines, an
infinite streamed world, a CPU rasteriser that already does greedy meshing, smooth light, ambient
occlusion, soft shadows, a sky, clouds, bloom and god-rays, on worker threads. What it asks of a
GPU backend, and what this branch gives:

| voxel-axle today | On `Renderer` |
|---|---|
| Chunk faces in `FaceMesh` (cell, direction, tile, run length, per-corner light bytes), projected and rasterised on CPU worker crews | Mesh each chunk once into a `MeshBuilder` — one `face()` per visible face, four corner colours, `layer` = the tile — and `uploadMesh` it. **The projection, clipping, z-buffer and fill disappear**; so do the raster crews and their column bands. |
| A re-mesh when a block changes | `builder.clear()`, mesh again, `updateMesh(handle, builder)`. Safe while frames are in flight. An empty builder (an all-air chunk, the last block mined) keeps the handle valid and draws nothing, so one handle per chunk is enough. |
| Frustum culling per chunk (`chunkVisible`) | `scene.addBounded(handle, tex, material, model, chunkBox)` — the frustum test is in `Scene`. |
| The 128 px HD atlas as a vertical strip with a CPU mip chain and anisotropic sampler | `Image::fromStrip(atlas, 128)` → layers → one texture with its mip chain (built at upload, alpha-weighted, coverage kept with `SamplerDesc.cutout` for the leaves), anisotropy and no bleeding between tiles. |
| Smooth light + AO computed per corner *per frame* (the sun moves) | Bake `block RGB` and a `sky` factor into the vertex colour once per light change, and let the day cycle drive a scene uniform — see below. |
| Transparent water, leaves with holes | `Material.opacity` (blended, sorted far to near by the chunk box's centre, since chunks share an identity model) and `Material.cutoff` (alpha test; no sorting, writes depth). |
| Torch light | A `PointLight` per torch near the camera (eight at a time), on top of the baked block light — `Material::voxel()` has `lampLight` 1 and `directLight` 0, so torches light it and the sun does not. |
| Mobs (box models), selection wireframe | `MeshBuilder` boxes with a model matrix per mob; a wireframe is a thin-box mesh. |
| HUD, hotbar, menus, text (`Frame`, `BitmapFont`) | `renderer.overlay()` — the same `Frame`. **No change.** |
| Sky gradient, sun and moon discs, clouds, god-rays, bloom, underwater tint | **Not provided by this branch.** See the next section. |
| Worker threads for raster | Gone from the 3-D path; the light engine and mesher threads stay. `Renderer` itself is single-threaded, like the window. |

### The one thing the generic shader needed, and how it is met

voxel's light is not static: the sun moves, so every corner's light changes every frame, and the
CPU path recomputes it per corner per frame. Re-baking every vertex of a streamed world each frame
would give back everything the GPU won. The way out is to split the baked light into the two parts
that actually vary on different schedules:

* **block light** (torches) — changes when a block changes; baked into the vertex colour's RGB;
* **sky light** — changes with the time of day; baked into the vertex colour's *alpha* as "how
  much of the sky reaches this corner" (0..255, ambient occlusion folded in), and multiplied by a
  **scene-wide sky tint** the program sets each frame (`Scene::setSkyLight`).

With `Material::voxel()` the shader computes `light = vertexRGB + skyTint × vertexA`. Day turns to
night by changing one colour, with no re-mesh and no re-upload. Soft sun shadows and one-bounce
colour bleed are *not* in this model — they are screen-space or per-frame effects of the CPU
renderer and would need their own passes.

### What the mesher's side looks like

Illustrative, and not compiled — voxel-axle's `ChunkMesher` already holds every number used
here (`FaceMesh` in `kworld/meshbuf.axle`: per face the cell, `(dir << 8) | tile`, the run
length, two light bytes per corner, and an ambient-occlusion byte of two bits per corner):

```rs
fn meshSlot(b : MeshBuilder, m : FaceMesh, slot : i32) : void {
    b.clear();                                   // keeps the storage: no allocation after warm-up
    for (i of 0..m.fcount[slot]) {
        let f = slot * World::MAX_FACES_PER_CHUNK + i;
        let dir  = (m.ftile[f] >> 8) & 7;
        let tile = m.ftile[f] & 0xFF;            // the texture-array layer
        let corners = faceCorners(m, f, dir);    // 4 world-space Vec3, counter-clockwise from outside
        let c0 = bakedLight(m, f, 0);            // MeshBuilder::rgba(blockR, blockG, blockB, sky)
        let c1 = bakedLight(m, f, 1);            //   — the nibbles x17, the occlusion folded into `sky`
        let c2 = bakedLight(m, f, 2);
        let c3 = bakedLight(m, f, 3);
        b.face(corners[0], corners[1], corners[2], corners[3], normalOf(dir), tile, c0, c1, c2, c3);
    }
}

// on a block edit or a chunk arriving:
meshSlot(builder, faces, slot);
renderer.updateMesh(chunk[slot], builder);       // or uploadMesh the first time

// every frame:
scene.reset();
scene.setCamera(camera);
scene.setSkyLight(daylight.skyColour());         // the whole day cycle is this one call
for (s of 0..slots) {
    scene.addBounded(chunk[s], atlas, Material::voxel(), Mat4::identity(), chunkBox(s));
}
```

### What would still have to be written

Said plainly, because a port is not a recompile:

1. **The sky.** Clear colour plus fog gets a horizon; the gradient, the sun and moon discs and the
   cloud dome (a ray-marched dome in the CPU renderer) are CPU code today. The honest first step is
   to keep rendering them on the CPU into a screen-sized buffer once per frame and upload it as a
   background texture; a sky pass in the GPU renderer is the proper one and a candidate for a custom
   shader hook (below).
2. **Post effects** (bloom, god-rays, underwater): render-to-texture and a full-screen pass. The
   backend has one render pass and no off-screen targets.
3. **The mesher** must emit `MeshBuilder` faces. It already knows everything needed (cell,
   direction, tile, run length, corner light bytes); the work is the vertex write, not the
   algorithm.
4. **Texture streaming** is not needed (one atlas), but **mesh memory** is: see the limits.

None of these needs a design change in smalt; (1) and (2) are what "custom shader / render
target" support would give, and are the next step, not this one.

## Limits and next steps

* **Linux type-checks but has not been built or run** — see the status note at the top.
* **No custom shaders.** One lit pipeline (plus the overlay). A user shader hook would be a
  `Material` carrying a pipeline handle; the pieces it needs (pipeline layout, descriptor sets,
  the frame block) are already shaped for it.
* **No render targets, no post effects, no shadows, no MSAA, no HDR, no instancing.**
* **Meshes are host-visible**, written by `memcpy`. A discrete GPU reads them across the bus (the
  heap prefers device-local host-visible memory where it exists). A staged upload to device-only
  memory is the next step for large static scenes.
* **Textures are uploaded synchronously** (a one-shot submit and a wait). Fine for load time, not
  for streaming textures every frame.
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
