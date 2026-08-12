import Foundation

/// A native-Swift reader for **PMX**: the MikuMikuDance / MikuMikuMoving 3D model format
/// (versions 2.0 and 2.1).
///
/// PMX is a binary container holding a textured triangle mesh plus a rig (bones, morphs, IK, rigid
/// bodies, joints, soft bodies). `SwiftPMX` reads the **geometry** (vertex positions and the
/// triangle index buffer) plus the material section's index ranges (`Mesh.submeshes`, so a single
/// part can be isolated from a whole-model PMX), and skips everything else, including all text
/// fields (so no Unicode / ICU dependency is needed; the only reason a PMX reader normally needs
/// one is to *decode* the names this library discards).
///
/// This is a clean-room implementation of the documented PMX 2.0/2.1 byte layout, modelled on the
/// structure of oguna/MMDFormats (CC0). Pure Swift, no platform-specific dependencies.
///
/// ```swift
/// let mesh = try PMX.read(contentsOf: url)          // right-handed, welded, degenerate faces dropped
/// print(mesh.positions.count, mesh.triangleCount)
///
/// for sub in mesh.submeshes {                        // isolate one material's triangles
///     let range = sub.indexOffset ..< sub.indexOffset + sub.indexCount
///     print("material \(sub.materialIndex): \(sub.indexCount / 3) triangles")
/// }
/// ```
public enum PMX {

    // MARK: Result

    /// One contiguous run of `Mesh.indices` belonging to a single PMX material: the material
    /// section's own segmentation of the face buffer, recovered without decoding any text.
    public struct Submesh: Sendable, Equatable {
        /// Start of this run in `Mesh.indices`.
        public var indexOffset: Int
        /// Length of this run (always a multiple of 3).
        public var indexCount: Int
        /// Index into the PMX file's material list (0-based, file order).
        public var materialIndex: Int

        public init(indexOffset: Int, indexCount: Int, materialIndex: Int) {
            self.indexOffset = indexOffset
            self.indexCount = indexCount
            self.materialIndex = materialIndex
        }
    }

    /// An indexed triangle mesh: unique `positions` and a flat `indices` buffer (3 per triangle).
    public struct Mesh: Equatable, Sendable {
        public var positions: [SIMD3<Float>]
        public var indices: [UInt32]
        /// Per-material index ranges recovered from the PMX material section, in file order.
        ///
        /// Empty if the material section couldn't be read (e.g. a truncated buffer).
        public var submeshes: [Submesh]

        public init(positions: [SIMD3<Float>], indices: [UInt32], submeshes: [Submesh] = []) {
            self.positions = positions
            self.indices = indices
            self.submeshes = submeshes
        }

        public var vertexCount: Int { positions.count }
        public var triangleCount: Int { indices.count / 3 }

        /// Axis-aligned bounds, or nil for an empty mesh.
        public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
            guard var lo = positions.first else { return nil }
            var hi = lo
            for p in positions {
                lo = SIMD3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                hi = SIMD3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
            }
            return (lo, hi)
        }
    }

    // MARK: Options

    /// How the raw PMX geometry is post-processed.
    public struct Options: Sendable {
        /// Convert MMD's left-handed, Y-up frame (DirectX convention) to right-handed by negating Z
        /// and reversing triangle winding (so face normals stay outward).
        ///
        /// Default `true`.
        public var convertToRightHanded: Bool
        /// Merge vertices closer than this (model units).
        ///
        /// PMX duplicates positions at UV/material seams, so welding restores connectivity; `nil`
        /// keeps the original PMX indexing. Default `1e-4`.
        public var weldEpsilon: Float?
        /// Drop zero-area triangles.
        ///
        /// PMX stores edge/point-draw primitives as degenerate faces. Default `true`.
        public var dropDegenerate: Bool
        /// Uniform scale applied to every coordinate.
        ///
        /// MMD models are roughly 8 units ≈ 1 m, so pass a scale if you need real-world units.
        /// Default `1` (faithful extraction).
        public var scale: Float

        public init(
            convertToRightHanded: Bool = true, weldEpsilon: Float? = 1e-4,
            dropDegenerate: Bool = true, scale: Float = 1
        ) {
            self.convertToRightHanded = convertToRightHanded
            self.weldEpsilon = weldEpsilon
            self.dropDegenerate = dropDegenerate
            self.scale = scale
        }

        public static var `default`: Options { Options() }
    }

    // MARK: Errors

    public enum Error: Swift.Error, Equatable, Sendable {
        case empty
        case truncated
        case badMagic
        case unsupportedVersion(Float)
        case malformedSetting
    }

    // MARK: Entry points

    /// Read a PMX file at `url`.
    public static func read(contentsOf url: URL, options: Options = .default) throws -> Mesh {
        try read(data: try Data(contentsOf: url), options: options)
    }

    /// Read PMX bytes.
    public static func read(data: Data, options: Options = .default) throws -> Mesh {
        guard !data.isEmpty else { throw Error.empty }
        let (positions, faces, triangleMaterialIds) = try parse(data: data, options: options)
        // Build the triangle soup (apply winding here so welding sees final corners), carrying a
        // per-triangle material id in lockstep so a pre-weld degenerate drop can't desync it from
        // the geometry it labels.
        var soup = [SIMD3<Float>]()
        soup.reserveCapacity(faces.count)
        var materialIds: [Int32]? = triangleMaterialIds != nil ? [] : nil
        if triangleMaterialIds != nil { materialIds!.reserveCapacity(faces.count / 3) }
        var t = 0
        while t + 2 < faces.count {
            let triIndex = t / 3
            let a = faces[t]
            let b = faces[t + 1]
            let c = faces[t + 2]
            t += 3
            if options.dropDegenerate, a == b || b == c || a == c { continue }
            if options.convertToRightHanded {
                soup.append(positions[a])
                soup.append(positions[c])
                soup.append(positions[b])
            } else {
                soup.append(positions[a])
                soup.append(positions[b])
                soup.append(positions[c])
            }
            if let ids = triangleMaterialIds { materialIds!.append(ids[triIndex]) }
        }
        var mesh = options.weldEpsilon.map { weld(soup, epsilon: $0) } ?? indexedSoup(soup)
        if options.dropDegenerate {
            let (m, ids) = dropDegenerateTriangles(mesh, materialIds: materialIds)
            mesh = m
            materialIds = ids
        }
        if let ids = materialIds { mesh.submeshes = buildSubmeshes(materialIds: ids) }
        return mesh
    }

    /// Sniff: a PMX file begins with the ASCII signature `"PMX "` (0x50 0x4D 0x58 0x20).
    public static func looksLikePMX(_ data: Data) -> Bool {
        data.count >= 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4D
            && data[data.startIndex + 2] == 0x58 && data[data.startIndex + 3] == 0x20
    }

    // MARK: Parse (positions + flat face index list + per-triangle material id)

    private static func parse(data: Data, options: Options)
        throws -> (positions: [SIMD3<Float>], faces: [Int], triangleMaterialIds: [Int32]?)
    {
        try data.withUnsafeBytes {
            (raw: UnsafeRawBufferPointer) -> ([SIMD3<Float>], [Int], [Int32]?) in
            var cur = Cursor(base: raw.baseAddress!, count: raw.count)

            // Header: "PMX " magic + version.
            guard try cur.u8() == 0x50, try cur.u8() == 0x4D, try cur.u8() == 0x58,
                try cur.u8() == 0x20
            else { throw Error.badMagic }
            let version = try cur.f32()
            guard version == 2.0 || version == 2.1 else { throw Error.unsupportedVersion(version) }

            // Setting block: count (>= 8) then that many bytes; the first 8 are what we need.
            let settingCount = Int(try cur.u8())
            guard settingCount >= 8 else { throw Error.malformedSetting }
            _ = try cur.u8()  // encoding (names only, unused)
            let additionalUV = Int(try cur.u8())
            let vertexIndexSize = Int(try cur.u8())
            let textureIndexSize = Int(try cur.u8())
            _ = try cur.u8()  // material index size
            let boneIndexSize = Int(try cur.u8())
            _ = try cur.u8()  // morph index size
            _ = try cur.u8()  // rigidbody index size
            try cur.skip(settingCount - 8)

            // Model info: 4 length-prefixed strings (name, english name, comment, english comment).
            for _ in 0..<4 { try cur.skipString() }

            // Vertices: position only; skip normal/uv/additional-uv/skinning/edge.
            let scale = options.scale
            let vertexCount = Int(try cur.i32())
            guard vertexCount >= 0 else { throw Error.truncated }
            var positions = [SIMD3<Float>]()
            positions.reserveCapacity(vertexCount)
            for _ in 0..<vertexCount {
                let x = try cur.f32()
                let y = try cur.f32()
                let z = try cur.f32()
                let zz = options.convertToRightHanded ? -z : z
                positions.append(SIMD3(x * scale, y * scale, zz * scale))
                try cur.skip(12 + 8 + additionalUV * 16)  // normal(12) + uv(8) + uva
                try cur.skipSkinning(boneIndexSize: boneIndexSize)
                try cur.skip(4)  // edge scale
            }

            // Faces: flat index buffer, every 3 = a triangle.
            let indexCount = Int(try cur.i32())
            guard indexCount >= 0 else { throw Error.truncated }
            var faces = [Int]()
            faces.reserveCapacity(indexCount)
            for _ in 0..<indexCount {
                let idx = try cur.index(vertexIndexSize)
                guard idx >= 0, idx < positions.count else { throw Error.truncated }
                faces.append(idx)
            }

            // Textures + materials: recovers the submesh table (Mesh.submeshes) without decoding
            // any text: every name/memo is stepped over with skipString(). This is best-effort: the
            // geometry above is already complete and valid, so a truncated/malformed tail here just
            // means no submesh info, not a failed read.
            let triangleMaterialIds: [Int32]? = try? {
                let textureCount = Int(try cur.i32())
                guard textureCount >= 0 else { throw Error.truncated }
                for _ in 0..<textureCount { try cur.skipString() }

                let materialCount = Int(try cur.i32())
                guard materialCount >= 0 else { throw Error.truncated }
                let triangleCount = indexCount / 3
                var ids = [Int32]()
                ids.reserveCapacity(triangleCount)
                for m in 0..<materialCount {
                    try cur.skipString()  // name
                    try cur.skipString()  // english name
                    try cur.skip(16 + 12 + 4 + 12)  // diffuse + specular + specularity + ambient
                    _ = try cur.u8()  // draw flags
                    try cur.skip(16 + 4)  // edge color + edge scale
                    try cur.skip(textureIndexSize)  // texture index
                    try cur.skip(textureIndexSize)  // sphere texture index
                    _ = try cur.u8()  // sphere mode
                    let sharedToonFlag = try cur.u8()
                    try cur.skip(sharedToonFlag == 0 ? textureIndexSize : 1)  // toon value
                    try cur.skipString()  // memo
                    let surfaceCount = Int(try cur.i32())
                    guard surfaceCount >= 0, surfaceCount % 3 == 0 else { throw Error.truncated }
                    let triCount = surfaceCount / 3
                    guard ids.count + triCount <= triangleCount else { throw Error.truncated }
                    for _ in 0..<triCount { ids.append(Int32(m)) }
                }
                guard ids.count == triangleCount else { throw Error.truncated }
                return ids
            }()

            return (positions, faces, triangleMaterialIds)
        }
    }

    // MARK: Mesh assembly

    /// Merge coincident vertices by quantizing to a grid of size `epsilon`.
    static func weld(_ soup: [SIMD3<Float>], epsilon: Float) -> Mesh {
        let inv = 1.0 / Swift.max(epsilon, .leastNormalMagnitude)
        var map = [SIMD3<Int32>: UInt32](minimumCapacity: soup.count / 2)
        var positions = [SIMD3<Float>]()
        positions.reserveCapacity(soup.count / 2)
        var indices = [UInt32]()
        indices.reserveCapacity(soup.count)
        for v in soup {
            let key = SIMD3<Int32>(
                Int32((v.x * inv).rounded()),
                Int32((v.y * inv).rounded()),
                Int32((v.z * inv).rounded()))
            if let idx = map[key] {
                indices.append(idx)
            } else {
                let idx = UInt32(positions.count)
                map[key] = idx
                positions.append(v)
                indices.append(idx)
            }
        }
        return Mesh(positions: positions, indices: indices)
    }

    /// Index a soup without welding (every corner becomes its own vertex).
    static func indexedSoup(_ soup: [SIMD3<Float>]) -> Mesh {
        Mesh(positions: soup, indices: (0..<UInt32(soup.count)).map { $0 })
    }

    /// Drop triangles whose three vertices aren't distinct (post-weld degenerate faces: welding can
    /// collapse a triangle to zero area even when its source indices were all different).
    ///
    /// Threads an optional per-triangle material id in lockstep so it stays aligned with the
    /// surviving triangles.
    static func dropDegenerateTriangles(_ m: Mesh, materialIds: [Int32]? = nil) -> (Mesh, [Int32]?)
    {
        var indices = [UInt32]()
        indices.reserveCapacity(m.indices.count)
        var ids: [Int32]? = materialIds != nil ? [] : nil
        if materialIds != nil { ids!.reserveCapacity(materialIds!.count) }
        var t = 0
        var triIndex = 0
        while t + 2 < m.indices.count {
            let a = m.indices[t]
            let b = m.indices[t + 1]
            let c = m.indices[t + 2]
            t += 3
            if a != b, b != c, a != c {
                indices.append(a)
                indices.append(b)
                indices.append(c)
                if let mids = materialIds { ids!.append(mids[triIndex]) }
            }
            triIndex += 1
        }
        return (Mesh(positions: m.positions, indices: indices), ids)
    }

    /// Collapse a per-triangle material id list into contiguous `Submesh` ranges.
    ///
    /// Drops never reorder triangles, only remove them, so each material's surviving triangles
    /// remain one contiguous run in file order.
    static func buildSubmeshes(materialIds: [Int32]) -> [Submesh] {
        var result: [Submesh] = []
        var i = 0
        while i < materialIds.count {
            let material = materialIds[i]
            var j = i + 1
            while j < materialIds.count, materialIds[j] == material { j += 1 }
            result.append(
                Submesh(indexOffset: i * 3, indexCount: (j - i) * 3, materialIndex: Int(material)))
            i = j
        }
        return result
    }

    // MARK: Byte cursor

    /// A bounds-checked little-endian sequential reader.
    ///
    /// Lives only inside `withUnsafeBytes` so the raw pointer never escapes.
    private struct Cursor {
        let base: UnsafeRawPointer
        let count: Int
        var off = 0

        mutating func ensure(_ n: Int) throws {
            guard n >= 0, off + n <= count else { throw Error.truncated }
        }

        mutating func u8() throws -> UInt8 {
            try ensure(1)
            defer { off += 1 }
            return base.advanced(by: off).loadUnaligned(as: UInt8.self)
        }
        mutating func i32() throws -> Int32 {
            try ensure(4)
            defer { off += 4 }
            return base.advanced(by: off).loadUnaligned(as: Int32.self)
        }
        mutating func f32() throws -> Float {
            try ensure(4)
            defer { off += 4 }
            return base.advanced(by: off).loadUnaligned(as: Float.self)
        }
        mutating func skip(_ n: Int) throws {
            try ensure(n)
            off += n
        }

        /// A length-prefixed (Int32) byte string; we only step over it.
        mutating func skipString() throws { try skip(Int(try i32())) }

        /// A PMX variable-width index.
        ///
        /// Sizes 1/2 are unsigned; size 4 is Int32. Face references are always non-negative.
        mutating func index(_ size: Int) throws -> Int {
            switch size {
            case 1: return Int(try u8())
            case 2:
                try ensure(2)
                defer { off += 2 }
                return Int(base.advanced(by: off).loadUnaligned(as: UInt16.self))
            default: return Int(try i32())
            }
        }

        /// Step over one vertex's skinning payload (size depends on the BDEF/SDEF/QDEF type byte and
        /// the model's bone-index width).
        mutating func skipSkinning(boneIndexSize: Int) throws {
            let type = try u8()
            switch type {
            case 0: try skip(boneIndexSize)  // BDEF1
            case 1: try skip(2 * boneIndexSize + 4)  // BDEF2
            case 2: try skip(4 * boneIndexSize + 16)  // BDEF4
            case 3: try skip(2 * boneIndexSize + 4 + 36)  // SDEF (+ c/r0/r1)
            case 4: try skip(4 * boneIndexSize + 16)  // QDEF
            default: throw Error.truncated
            }
        }
    }
}
