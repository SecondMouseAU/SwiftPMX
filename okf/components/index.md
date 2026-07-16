---
type: component
title: Components index
resource: https://github.com/SecondMouseAU/SwiftPMX
tags: [index]
description: Public modules / API surfaces exposed by SwiftPMX.
timestamp: 2026-06-25
---

# Components

- **`SwiftPMX`** (library) — reads a `.pmx` file (versions 2.0/2.1) and returns mesh geometry: vertex
  positions, the triangle index buffer, and per-material submesh ranges (`Mesh.submeshes`, for
  isolating a single part from a whole-model PMX). Handles left-handed → right-handed conversion,
  seam welding, degenerate-face culling, and uniform scale.
