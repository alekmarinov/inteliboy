# InteliBoy

An appliance. A Linux From Scratch image that boots into a 3D talking head,
listens, answers, and writes itself new capabilities when asked.

```
   lfs ──builds──▶ the image
                     │
                     ├── avatari   the face: a talking head, C11, straight to KMS
                     └── cogiti    the brain: resolves, decides, supervises, remembers
                            └── links reflexi, the reflex: intent resolution in ~16 µs
```

**This repository holds no product code.** The components are separate
repositories with their own history, remotes and release cadence. Here live the
map, the cross-component changes, the product roadmap, and the known-good set.

    make list       the components and where they are
    make status     branch, dirty and unpushed, per component
    make verify     status, then every component's own tests
    make lock       write the current HEADs into versions.lock

`components.toml` says where the components are. They are siblings of this
directory, so every path begins `../`.

`lfs` is deliberately not a component. It is a build tool with five distros and
other users — InteliBoy is one of its clients. See `docs/lfs-products.md`.

`cogiti` is deliberately general. It is an orchestrator for any spoken agentic
system; InteliBoy is the first deployment of it, and `docs/adapters.md` is the
binding.

    CLAUDE.md            how the orchestrator session operates
    docs/roadmap.md      thirteen stages, each one shippable
    docs/subprojects.md  the component map and what runs in parallel
    docs/DEVELOPMENT.md  how ten repositories are kept in step
    changes/             one directory per cross-component change
