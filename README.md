# SwiftPMX

A small, dependency-free **native-Swift reader for PMX** — the MikuMikuDance / MikuMikuMoving 3D
model format (versions 2.0 and 2.1).

PMX is a binary container holding a textured triangle mesh plus a rig (bones, morphs, IK, rigid
bodies, joints, soft bodies). SwiftPMX extracts the **geometry** — vertex positions and the triangle
index buffer — and skips everything else, including all text fields. Because it never decodes names,
it needs **no ICU / Unicode dependency** (the usual reason a PMX parser pulls one in).

- Pure Swift, no dependencies, Linux + Apple platforms.
- Clean-room implementation of the documented PMX 2.0/2.1 byte layout (structure modelled on
  [oguna/MMDFormats](https://github.com/oguna/MMDFormats), CC0).
- Handles the things that bite mesh consumers: **left-handed → right-handed** conversion, **seam
  welding**, **degenerate edge/point-draw face culling**, and **uniform scale**.

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

## Scope

SwiftPMX is a **geometry reader**. It does not load rig/animation data, materials, or textures, and
it does not write any format. It is intended as the front-end that turns a PMX model into a plain
indexed mesh you can feed into your own pipeline (rendering, CAD reconstruction, conversion, …).

## License

MIT. The reference byte layout (oguna/MMDFormats) is CC0.
