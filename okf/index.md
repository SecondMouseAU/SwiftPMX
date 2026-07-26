---
type: repo
title: SwiftPMX
resource: https://github.com/SecondMouseAU/SwiftPMX
tags: [pmx, mikumikudance, mesh, geometry, import, swift]
description: Native-Swift reader for PMX (MikuMikuDance) 3D model geometry.
timestamp: 2026-06-25
---

# SwiftPMX

A small, dependency-free **native-Swift reader for PMX** — the MikuMikuDance / MikuMikuMoving 3D model
format (2.0 and 2.1). PMX is a binary container holding a textured triangle mesh plus a rig; SwiftPMX
extracts the **geometry** (vertex positions and the triangle index buffer) plus per-material submesh
ranges, and skips everything else, including all text fields — so it needs no ICU/Unicode dependency.
Clean-room implementation of the documented byte layout.

## Role in the ecosystem

- **Cluster:** kernel
- **Depends on:** nothing (leaf — pure Swift, Linux + Apple)
- **Feeds products:** PMX mesh import (e.g. OCCTReconstruct's `--pmx2stl` / `--pmx2obj` path)

## Components

See [`components/`](components/index.md) for the public surface.

## References

See [`references/`](references/index.md) for the PMX format references.

## Policies

- [Query `context` first for OCCT / OCCTSwift docs](policies/context-first.md)
- [Documentation updates are mandatory](policies/docs-current.md)
- [No em-dashes, banned words in prose](policies/writing-style.md)
- [Search before building](policies/search-before-building.md)
