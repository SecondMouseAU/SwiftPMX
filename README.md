# SwiftPMX

[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSecondMouseAU%2FSwiftPMX%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/SecondMouseAU/SwiftPMX)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSecondMouseAU%2FSwiftPMX%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/SecondMouseAU/SwiftPMX)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-page-2ea44f)](https://secondmouseau.github.io/SwiftPMX/)

📖 **Documentation:** <https://secondmouseau.github.io/SwiftPMX/>

A small, dependency-free **native-Swift reader for PMX** — the MikuMikuDance / MikuMikuMoving 3D
model format (versions 2.0 and 2.1).

PMX is a binary container holding a textured triangle mesh plus a rig (bones, morphs, IK, rigid
bodies, joints, soft bodies). SwiftPMX extracts the **geometry** — vertex positions and the triangle
index buffer — plus the material section's index ranges (so you can isolate a single part from a
whole-model PMX), and skips everything else, including all text fields. Because it never decodes
names, it needs **no ICU / Unicode dependency** (the usual reason a PMX parser pulls one in).

- Pure Swift, no dependencies, Linux + Apple platforms.
- Clean-room implementation of the documented PMX 2.0/2.1 byte layout (structure modelled on
  [oguna/MMDFormats](https://github.com/oguna/MMDFormats), CC0).
- Handles the things that bite mesh consumers: **left-handed → right-handed** conversion, **seam
  welding**, **degenerate edge/point-draw face culling**, and **uniform scale**.
- Recovers per-material **submesh** index ranges, so a single part (the carbody skin, a prop) can be
  pulled out of a whole-model PMX — without decoding a single material name.

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/SecondMouseAU/SwiftPMX.git", from: "1.0.0"),
],
// target:
.target(name: "YourTarget", dependencies: [.product(name: "SwiftPMX", package: "SwiftPMX")]),
```

## Use

```swift
import SwiftPMX

let mesh = try PMX.read(contentsOf: url)   // right-handed, welded, degenerate faces dropped
print(mesh.vertexCount, mesh.triangleCount)
for t in 0..<mesh.triangleCount {
    let i = t * 3
    let (a, b, c) = (mesh.indices[i], mesh.indices[i + 1], mesh.indices[i + 2])
    // mesh.positions[Int(a)] ...
}
```

### Options

Everything is configurable via `PMX.Options`:

```swift
var opts = PMX.Options()
opts.convertToRightHanded = true   // negate Z + reverse winding (MMD is LH/Y-up). Default true.
opts.weldEpsilon = 1e-4            // merge seam-duplicated vertices; nil keeps PMX indexing. Default 1e-4.
opts.dropDegenerate = true         // drop zero-area edge/point-draw faces. Default true.
opts.scale = 1.0                   // MMD models are ~8 units ≈ 1 m; scale for real-world units.
let raw = try PMX.read(contentsOf: url, options: opts)
```

`PMX.looksLikePMX(data)` sniffs the `"PMX "` signature if you need to detect the format.

### Submeshes

`mesh.submeshes` gives one `PMX.Submesh` per material — a contiguous `(indexOffset, indexCount)` run
into `mesh.indices`, in file order, plus that material's `materialIndex`. This is the material
section's own segmentation of the face buffer, recovered without decoding a single name: useful for
isolating one part (say, the carbody skin) out of a whole-model PMX.

```swift
for sub in mesh.submeshes {
    let partIndices = mesh.indices[sub.indexOffset ..< sub.indexOffset + sub.indexCount]
    // build a standalone Mesh from partIndices + mesh.positions ...
}
```

It's empty if the material section can't be read (e.g. a truncated buffer) — the geometry above is
unaffected either way.

## Scope

SwiftPMX is a **geometry reader**. It reads material *index ranges* for submeshing but not material
properties (colours, textures, names), and it does not load rig/animation data or write any format.
It is intended as the front-end that turns a PMX model into a plain indexed mesh you can feed into
your own pipeline (rendering, CAD reconstruction, conversion, …).

## License

MIT. The reference byte layout (oguna/MMDFormats) is CC0.
