# 2026-09-11-surfaces-beside-the-face — a browser on the screen, next to the head

Status: design, unapproved
Decided by: Alexander Marinov, 2026-09-11 (the four questions below)

## The ask

Show an external graphical application — the cog browser, the vrfiles file
manager — on the appliance's screen beside the talking head. avatari holds the
only framebuffer, so avatari has to serve those surfaces: that is a
compositor's job, and the decision is that avatari does it.

## What the survey established

**The design already named this.** `avatari/src/scene.h:3-7`, the first lines
of the header: the renderer draws "a product photo, a chart, *a browser
surface*". `avatari/docs/lfs-build.md:68` already carries the cost row. And
`SCENE_KIND_CAMERA` is the working precedent — an object whose content is a
live buffer produced by something else, drawn by the unchanged panel shader.

**vrfiles costs nothing.** It needs `wl_compositor`, `wl_subcompositor`,
`wl_shm`, `wl_seat`, `xdg_shell` and a Wayland EGL, and it accepts whatever
rectangle the compositor configures (default 1024x768; fullscreen is opt-in).
Every dependency is already in BLFS 12.4 and the package is 176 KB, because it
carries no engine. It must run `COG_PLATFORM_NAME=wl`: cog's `drm` platform
takes DRM master and cannot share a screen with avatari.

**cubewl proves the shape on this hardware class** — ~3,100 lines, wlroots
0.18.2 vendored static, cog as the demo client, and a pointer model worth
stealing: un-project through the inverse of the exact MVP, ray/plane against
the client quads, uv scaled to surface size, focus re-evaluated every frame
because the quads move under a stationary mouse.

**But cubewl's cheapest trick does not transfer.** It takes the raw GL texture
name out of wlroots' GLES2 renderer. avatari is desktop **GL 4.1 core**
(`platform_kms.c:373` binds `EGL_OPENGL_API`), so that name is not valid in
its context. avatari must import each client dmabuf itself —
`eglCreateImage` + `glEGLImageTargetTexture2DOES` — using wlroots, if at all,
only for protocol, backend and allocator. This is the single most important
finding and it is an inference from two surveys, not something either proved.
It is what step 1 tests.

## The four decisions

1. **avatari may be a compositor.** `avatari/CLAUDE.md:21` ("No display
   server... no compositor") and `:137` ("if a change makes the LFS build
   depend on GLFW, X11, or Wayland, it is wrong") and §2's "that is the entire
   list" all have to be amended. Line 21 was always a statement about what sits
   *beneath* avatari; serving surfaces does not put a display server under it.
   Line 137 and §2 are genuine amendments and are the user's to make.
2. **A surface object dies with either connection.** `scene.h:16-19` assumes
   one connection per object; a surface has two — the brain that asked for a
   browser and the browser painting it. Kill either, kill both.
3. **`screenshot` will not be installed**, so the privacy objection is moot
   rather than answered. See *Not settled* — this may mean the op is removed
   or merely not shipped, and the difference costs something.
4. **wlroots statically linked, or hand-rolled** — whichever suits. wlroots is
   a new LFS package and a GLES2 renderer used only for its allocator;
   hand-rolling the subset cog needs is more code and no new dependency beyond
   `libwayland-server`. Step 1 does not decide it and does not need to.

## What it costs the distro

Already built as base packages, merely not selected into our image:
`24-make-wayland`, `24-make-wayland-protocols`, `24-make-libxkbcommon`,
`9-make-libinput`, `9-make-seatd`. Adding them is five lines in
`packages.list`. Only **wlroots** has no recipe anywhere.

## The three real costs, none of them the protocol

- **`platform_swap()` blocks the process on vblank** (`platform_kms.c:568`), and
  a compositor needs that time to service clients and dispatch frame callbacks.
  Fixing it breaks the four-function interface at `platform.h:78-89`.
- **There is no ortho pass.** Scene objects are unit quads in world space under
  the head's own perspective camera (`main.c:308-348`), so a client surface is
  not pixel-aligned, its text is resampled, and pointer routing is a ray/quad
  intersection rather than a rectangle hit test.
- **Input is the bigger half.** No pointer at all on the target, no notion of
  focus anywhere, `EV_KEY` only and deliberately no libevdev. A seat, a focus
  model, evdev pointer/touch, and `libxkbcommon` — non-optional, because
  `wl_keyboard` must send a keymap fd.

## Per repo

### avatari  [order 1]
step 1 — the experiment that can kill the idea for 200 lines:
  regenerate glad with `GL_OES_EGL_image` (`EGL_EXT_image_dma_buf_import` is
  already in the EGL loader and unused); a throwaway producer exporting a GBM
  bo and passing the fd by `SCM_RIGHTS` over the socket `ipc.c` already owns;
  a `kind:"surface"` object whose setter is a sibling of
  `scene_set_camera_frame`. No Wayland, no new package, no protocol semantics.
proves it: `--frames` and `--record`, which already exist. It answers the only
  two things that kill this outright — does dmabuf import work on the target
  GPU under a GL 4.1 core context, and does live content on a perspective quad
  look acceptable.
must also: build under `PLATFORM=desktop`. avatari's test command *is*
  `make PLATFORM=desktop`, so a KMS-only path is unverifiable by construction.

### cogiti  [order 2, only after step 1 passes]
Focus policy, client lifecycle and which clients may exist are orchestration.
avatari routes events to whichever surface the scene says has focus and does
not decide which that is.

### inteliboy [order 3]
`packages.list`, the cog and vrfiles packages, `COG_PLATFORM_NAME=wl`.

## Not settled

- **What "no screenshot" means.** cogiti never asks for one — the only
  dependency in the tree is `tools/verify-image.sh:57`. But the `screenshot`
  op over the socket is the only way to see what the appliance is showing
  without standing in front of it, and it is how the sleep/wake behaviour and
  the confirmation card were verified this week. Removing the op and not
  installing a screenshot *tool* are different decisions.
- **Escape quits avatari** (`main.c:790`). If a client holds focus on an
  appliance with no other exit, that is a hazard and nothing replaces it yet.
- **"Kill both" has a consequence worth naming**: cogiti restarts itself during
  a spoken software upgrade. Under this rule, updating the appliance closes any
  open browser.
- Whether the surface path is allowed to be GLES2, which would make wlroots'
  renderer usable directly and change the shape of everything above.

## Not in this change

Window management of any kind. `avatari/CLAUDE.md` §10 refuses "any GUI, menu,
or settings interface", and one client in one scene panel placed by
`scene_layout` is a panel, not a desktop. A taskbar, alt-tab, decorations,
minimise or drag-to-resize would be a desktop.
