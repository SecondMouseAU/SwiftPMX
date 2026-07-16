---
title: SwiftPMX
nav_order: 1
---

# SwiftPMX

A small, **native-Swift, dependency-free reader for PMX** — the MikuMikuDance / MikuMikuMoving 3D
model format (versions **2.0** and **2.1**).

PMX is a binary container holding a textured triangle mesh plus a full rig (bones, morphs, IK, rigid
bodies, joints, soft bodies). SwiftPMX reads the **geometry** — vertex positions and the triangle
index buffer — plus the material section's index ranges for submeshing, and skips everything else,
including all text fields. Because it never decodes names, it needs **no ICU / Unicode dependency**
(the usual reason a PMX parser pulls one in).

- Pure Swift, **zero dependencies**, builds on Apple platforms **and Linux**.
- Clean-room implementation of the documented PMX 2.0/2.1 byte layout (structure modelled on
  [oguna/MMDFormats](https://github.com/oguna/MMDFormats), CC0).
- Handles the things that bite mesh consumers: **left-handed → right-handed** conversion, **seam
  welding**, **degenerate edge/point-draw face culling**, and **uniform scale** — all configurable.
- Recovers per-material **submesh** index ranges, so a single part can be isolated from a whole-model
  PMX — without decoding a single material name.

PMX format reference: the community-maintained
[PMX 2.0/2.1 specification](https://gist.github.com/felixjones/f8a06bd48f9da9a4539f).

---

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/SecondMouseAU/SwiftPMX.git", from: "1.0.0"),
],
```

…and add the product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [.product(name: "SwiftPMX", package: "SwiftPMX")]
),
```

---

## Quick start

```swift
import SwiftPMX

// Defaults: right-handed, welded, degenerate faces dropped, scale 1.0.
let mesh = try PMX.read(contentsOf: url)

print(mesh.vertexCount, mesh.triangleCount)

for t in 0..<mesh.triangleCount {
    let i = t * 3
    let a = mesh.positions[Int(mesh.indices[i])]
    let b = mesh.positions[Int(mesh.indices[i + 1])]
    let c = mesh.positions[Int(mesh.indices[i + 2])]
    // … use the triangle (a, b, c)
}
```

Detect the format before reading:

```swift
let data = try Data(contentsOf: url)
guard PMX.looksLikePMX(data) else { /* not a PMX file */ return }
let mesh = try PMX.read(data: data)
```

Isolate one part (a material group) from a whole-model PMX:

```swift
for sub in mesh.submeshes {
    let partIndices = mesh.indices[sub.indexOffset ..< sub.indexOffset + sub.indexCount]
    // build a standalone PMX.Mesh from partIndices + mesh.positions ...
}
```

---

## API reference

### `PMX.read`

Two entry points — from a file URL, or from raw bytes. Both return a [`PMX.Mesh`](#pmxmesh) and throw
[`PMX.Error`](#pmxerror) on a malformed or unsupported file.

```swift
static func read(contentsOf url: URL, options: Options = .default) throws -> Mesh
static func read(data: Data,        options: Options = .default) throws -> Mesh
```

### `PMX.looksLikePMX`

A cheap signature sniff — `true` when `data` begins with the ASCII bytes `"PMX "`
(`0x50 0x4D 0x58 0x20`). Useful for content-based format dispatch.

```swift
static func looksLikePMX(_ data: Data) -> Bool
```

### `PMX.Mesh`

An indexed triangle mesh: unique `positions` and a flat `indices` buffer (three entries per triangle).

```swift
struct Mesh: Equatable, Sendable {
    var positions:  [SIMD3<Float>]
    var indices:    [UInt32]
    var submeshes:  [Submesh]       // per-material index ranges; [] if unreadable

    var vertexCount: Int            // positions.count
    var triangleCount: Int          // indices.count / 3
    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?   // nil for an empty mesh
}
```

`SIMD3<Float>` is the Swift standard-library type — SwiftPMX does **not** import the Apple-only `simd`
module, which is what keeps it Linux-portable.

### `PMX.Submesh`

One contiguous run of `Mesh.indices` belonging to a single PMX material — the material section's own
segmentation of the face buffer, recovered without decoding any text.

```swift
struct Submesh: Sendable, Equatable {
    var indexOffset:   Int   // start of this run in Mesh.indices
    var indexCount:    Int   // length of this run (always a multiple of 3)
    var materialIndex: Int   // index into the PMX file's material list (0-based, file order)
}
```

`Mesh.submeshes` is built by tracking a per-triangle material id through both degenerate-drop passes
(pre-weld and post-weld), so offsets stay correct even when a material's face range contains a
dropped face. It's empty when the material section can't be read — e.g. a truncated buffer — but that
never affects `positions` / `indices`, which are already complete and valid at that point.

### `PMX.Options`

Controls how the raw PMX geometry is post-processed. All fields have sensible defaults; construct with
the memberwise initializer or tweak `PMX.Options()`.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `convertToRightHanded` | `Bool` | `true` | MMD authors in a **left-handed, Y-up** frame (DirectX). When `true`, SwiftPMX negates Z and reverses triangle winding so the result is right-handed with outward-facing normals. Set `false` to keep native MMD coordinates. |
| `weldEpsilon` | `Float?` | `1e-4` | Merge vertices closer than this (model units). PMX duplicates positions at UV / material seams; welding restores connectivity. Pass `nil` to keep the original PMX indexing unchanged. |
| `dropDegenerate` | `Bool` | `true` | Drop zero-area triangles — PMX stores edge- and point-draw primitives as degenerate faces. |
| `scale` | `Float` | `1` | Uniform scale applied to every coordinate. See [Units](#units-and-scale). |

```swift
var opts = PMX.Options()
opts.weldEpsilon = nil          // keep raw PMX vertex indexing
opts.scale = 1.0 / 8.0          // MMD units → metres (≈ 8 units per metre)
let raw = try PMX.read(contentsOf: url, options: opts)
```

### `PMX.Error`

```swift
enum Error: Swift.Error, Equatable, Sendable {
    case empty                       // no bytes
    case truncated                   // ran off the end of the buffer
    case badMagic                    // missing the "PMX " signature
    case unsupportedVersion(Float)   // not 2.0 or 2.1
    case malformedSetting            // header setting block is too short
}
```

---

## Behaviour notes

### Coordinate system

MMD uses a **left-handed, Y-up** coordinate system (the DirectX convention). With the default
`convertToRightHanded: true`, SwiftPMX produces a **right-handed** mesh by negating the Z axis and
reversing triangle winding — so face normals remain outward and the mesh drops straight into
right-handed renderers and CAD kernels. This conversion has been verified byte-for-byte against
Assimp's PMX importer on a corpus of locomotive models.

### Units and scale

MMD models are authored at roughly **8 units ≈ 1 metre**. SwiftPMX does **not** rescale by default
(`scale = 1` gives faithful extraction) — apply a `scale` if your downstream needs real-world units.
For example, a model that should be ~3.5 m tall arrives ~28 units tall; pass `scale: 1.0 / 8.0` to get
metres.

### Welding and seams

PMX stores a shared vertex buffer, but authors duplicate positions wherever a UV or material seam
needs distinct attributes. Left as-is, those duplicates appear as cracks to any algorithm that relies
on topological connectivity (connected components, watertightness, reconstruction). The default
`weldEpsilon` of `1e-4` merges coincident positions back together; set it to `nil` if you specifically
want the original PMX indexing.

### Degenerate faces

A PMX material can request **edge** or **point** drawing; those primitives are encoded as zero-area
triangles in the index buffer. With `dropDegenerate: true` (the default) they're removed — once before
welding (index-duplicate corners) and once after (corners welding can collapse to the same vertex),
leaving only real surface triangles.

### Submeshes and material segmentation

PMX assigns each material a contiguous run of the face buffer (`surfaceCount`, sequential over the
index buffer) — that is a submesh table for free, no text decoding required. `mesh.submeshes` exposes
it as `(indexOffset, indexCount, materialIndex)` triples in file order.

The tricky part: `dropDegenerate` can remove faces from *inside* a material's range, at two different
points (pre-weld and post-weld). A per-triangle material id is threaded through both drops before the
final contiguous ranges are derived, so `submeshes` stays correct even when a material's range
contains a dropped face — including a face in the *middle* of the range.

---

## Scope

SwiftPMX is a **geometry reader**, by design. It does not:

- load rig or animation data (bones, morphs, IK, rigid bodies, joints, soft bodies);
- load material *properties* (colours, textures, UVs) — only each material's index range, for
  submeshing;
- decode model / material / bone **names** (it skips the text fields entirely);
- **write** any format.

It is intended as the front-end that turns a PMX model into a plain indexed mesh you can feed into your
own pipeline — rendering, CAD reconstruction, format conversion, measurement, and so on.

> **Content licensing.** The PMX *model files* you read usually carry their own redistribution terms
> set by the model's author (see the model's bundled readme). SwiftPMX itself imposes nothing, but
> bundling or redistributing third-party models is a separate question from using this library.

---

## Performance

Reading is a single linear pass over the file with bounds-checked little-endian loads; welding is an
O(*n*) hash on quantized positions. Typical character/vehicle models (tens of thousands of triangles)
parse in single-digit milliseconds.

---

## License & provenance

SwiftPMX is licensed **MIT**. It is a clean-room implementation of the documented PMX 2.0/2.1 byte
layout; the layout structure was cross-referenced against [oguna/MMDFormats](https://github.com/oguna/MMDFormats)
(CC0 / public domain). PMX and MikuMikuDance are the work of their respective authors.
