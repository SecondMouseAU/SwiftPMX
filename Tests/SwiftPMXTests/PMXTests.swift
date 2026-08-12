import Foundation
import Testing

@testable import SwiftPMX

@Suite("PMX reading")
struct PMXTests {

    /// Build a valid PMX 2.0 byte buffer: the given vertices + triangle index list.
    ///
    /// Encoding UTF-8, all index widths 1 byte, no additional UVs, BDEF1 skinning, no textures.
    /// `materials` is a list of per-material surface counts (index-buffer entries, so a multiple of
    /// 3) that must sum to `indices.count`; defaults to one material owning the whole index buffer.
    static func makePMX(
        vertices: [SIMD3<Float>], indices: [UInt8], version: Float = 2.0,
        materials: [Int]? = nil
    ) -> Data {
        var d = Data()
        func u8(_ v: UInt8) { d.append(v) }
        func i32(_ v: Int32) {
            var x = v
            withUnsafeBytes(of: &x) { d.append(contentsOf: $0) }
        }
        func f32(_ v: Float) {
            var x = v
            withUnsafeBytes(of: &x) { d.append(contentsOf: $0) }
        }

        d.append(contentsOf: [0x50, 0x4D, 0x58, 0x20])  // "PMX "
        f32(version)
        u8(8)  // setting count
        u8(1)  // encoding = UTF-8
        u8(0)  // additional UV = 0
        for _ in 0..<6 { u8(1) }  // index sizes = 1
        for _ in 0..<4 { i32(0) }  // 4 empty model-info strings

        i32(Int32(vertices.count))
        for v in vertices {
            f32(v.x)
            f32(v.y)
            f32(v.z)  // position
            f32(0)
            f32(0)
            f32(0)  // normal
            f32(0)
            f32(0)  // uv
            u8(0)  // skinning type BDEF1
            u8(0)  // bone index (1 byte)
            f32(0)  // edge scale
        }

        i32(Int32(indices.count))
        d.append(contentsOf: indices)

        i32(0)  // texture count = 0

        let surfaceCounts = materials ?? [indices.count]
        i32(Int32(surfaceCounts.count))
        for surfaceCount in surfaceCounts {
            i32(0)
            i32(0)  // name, english name (empty)
            for _ in 0..<11 { f32(0) }  // diffuse(4) + specular(3) + specularity(1) + ambient(3)
            u8(0)  // draw flags
            for _ in 0..<4 { f32(0) }  // edge color
            f32(0)  // edge scale
            u8(0)  // texture index (1 byte)
            u8(0)  // sphere texture index (1 byte)
            u8(0)  // sphere mode
            u8(1)  // shared toon flag = internal ref
            u8(0)  // toon value (1 byte, internal ref)
            i32(0)  // memo (empty)
            i32(Int32(surfaceCount))
        }
        return d
    }

    @Test("reads geometry, negates Z, reverses winding, culls degenerate")
    func readsGeometry() throws {
        let verts: [SIMD3<Float>] = [
            .init(0, 0, 0), .init(1, 0, 0), .init(0, 1, 0), .init(1, 1, 3),
        ]
        let mesh = try PMX.read(
            data: Self.makePMX(vertices: verts, indices: [0, 1, 2, 1, 3, 2, 0, 0, 1]))

        #expect(mesh.vertexCount == 4)
        #expect(mesh.triangleCount == 2)  // degenerate (0,0,1) dropped
        let b = try #require(mesh.bounds)
        #expect(abs(b.min.z - (-3)) < 1e-5)  // Z negated
        #expect(abs(b.max.z - 0) < 1e-5)
    }

    @Test("convertToRightHanded:false keeps native MMD Z")
    func keepsNativeFrame() throws {
        let verts: [SIMD3<Float>] = [.init(0, 0, 0), .init(1, 0, 0), .init(0, 0, 5)]
        var opts = PMX.Options()
        opts.convertToRightHanded = false
        let mesh = try PMX.read(
            data: Self.makePMX(vertices: verts, indices: [0, 1, 2]), options: opts)
        let b = try #require(mesh.bounds)
        #expect(abs(b.max.z - 5) < 1e-5)  // not negated
    }

    @Test("scale multiplies coordinates")
    func appliesScale() throws {
        let verts: [SIMD3<Float>] = [.init(0, 0, 0), .init(1, 0, 0), .init(0, 2, 0)]
        var opts = PMX.Options()
        opts.scale = 10
        let mesh = try PMX.read(
            data: Self.makePMX(vertices: verts, indices: [0, 1, 2]), options: opts)
        let b = try #require(mesh.bounds)
        #expect(abs(b.max.y - 20) < 1e-4)
    }

    @Test("welds seam-duplicated vertices; nil weld keeps them")
    func welds() throws {
        let verts: [SIMD3<Float>] = [
            .init(0, 0, 0), .init(1, 0, 0), .init(1, 1, 0),
            .init(0, 0, 0), .init(1, 1, 0), .init(0, 1, 0),
        ]
        let data = Self.makePMX(vertices: verts, indices: [0, 1, 2, 3, 4, 5])
        #expect(try PMX.read(data: data).vertexCount == 4)  // welded

        var raw = PMX.Options()
        raw.weldEpsilon = nil
        #expect(try PMX.read(data: data, options: raw).vertexCount == 6)  // unwelded soup
    }

    @Test("rejects bad magic and bad version")
    func rejects() {
        var bad = Data([0x46, 0x4F, 0x4F, 0x20])
        bad.append(Data(count: 32))
        #expect(throws: PMX.Error.self) { try PMX.read(data: bad) }

        let verts: [SIMD3<Float>] = [.init(0, 0, 0), .init(1, 0, 0), .init(0, 1, 0)]
        let v1 = Self.makePMX(vertices: verts, indices: [0, 1, 2], version: 1.0)
        #expect(throws: PMX.Error.self) { try PMX.read(data: v1) }
    }

    @Test("looksLikePMX sniffs the signature")
    func sniffs() {
        #expect(PMX.looksLikePMX(Data([0x50, 0x4D, 0x58, 0x20, 0, 0])))
        #expect(!PMX.looksLikePMX(Data([0x73, 0x6F, 0x6C, 0x69])))
    }

    @Test("submeshes recover per-material index ranges from the material section")
    func exposesSubmeshes() throws {
        let verts: [SIMD3<Float>] = [
            .init(0, 0, 0), .init(1, 0, 0), .init(0, 1, 0),
            .init(2, 0, 0), .init(0, 2, 0), .init(3, 0, 0),
        ]
        let indices: [UInt8] = [0, 1, 2, 1, 3, 2, 3, 4, 2, 0, 5, 1]
        let data = Self.makePMX(vertices: verts, indices: indices, materials: [3, 6, 3])
        let mesh = try PMX.read(data: data)

        #expect(mesh.triangleCount == 4)
        #expect(
            mesh.submeshes == [
                PMX.Submesh(indexOffset: 0, indexCount: 3, materialIndex: 0),
                PMX.Submesh(indexOffset: 3, indexCount: 6, materialIndex: 1),
                PMX.Submesh(indexOffset: 9, indexCount: 3, materialIndex: 2),
            ])
    }

    @Test("submesh offsets survive a pre-weld degenerate face dropped from a middle material")
    func submeshesSurvivePreWeldDegenerate() throws {
        // A deliberate index-duplicate triangle (6, 6, 7) in the *middle* material: this is the
        // case that exposes an off-by-N if the offset table is computed before the drop.
        let verts: [SIMD3<Float>] = (0..<8).map { SIMD3<Float>(Float($0), 0, 0) }
        let indices: [UInt8] = [
            0, 1, 2, 1, 3, 2,  // material 0, 2 triangles
            4, 5, 6, 6, 6, 7, 5, 7, 6,  // material 1, middle triangle is degenerate
            2, 3, 0, 3, 1, 0,  // material 2, 2 triangles
        ]
        let data = Self.makePMX(vertices: verts, indices: indices, materials: [6, 9, 6])
        let mesh = try PMX.read(data: data)

        #expect(mesh.triangleCount == 6)  // the one degenerate face was dropped
        #expect(
            mesh.submeshes == [
                PMX.Submesh(indexOffset: 0, indexCount: 6, materialIndex: 0),
                PMX.Submesh(indexOffset: 6, indexCount: 6, materialIndex: 1),
                PMX.Submesh(indexOffset: 12, indexCount: 6, materialIndex: 2),
            ])
    }

    @Test("submesh offsets survive a post-weld degenerate face dropped from a middle material")
    func submeshesSurvivePostWeldDegenerate() throws {
        // Vertex 8 sits within weldEpsilon of vertex 4, so triangle (4, 8, 6): three *distinct*
        // source indices, passing the pre-weld check, only collapses to zero area after welding.
        var verts: [SIMD3<Float>] = (0..<8).map { SIMD3<Float>(Float($0), 0, 0) }
        verts.append(SIMD3<Float>(4.00001, 0, 0))
        let indices: [UInt8] = [
            0, 1, 2, 1, 3, 2,  // material 0, 2 triangles
            4, 5, 6, 4, 8, 6, 5, 7, 6,  // material 1, middle triangle collapses on weld
            2, 3, 0, 3, 1, 0,  // material 2, 2 triangles
        ]
        let data = Self.makePMX(vertices: verts, indices: indices, materials: [6, 9, 6])
        let mesh = try PMX.read(data: data)

        #expect(mesh.vertexCount == 8)  // vertex 8 welded into vertex 4
        #expect(mesh.triangleCount == 6)  // the one post-weld degenerate face was dropped
        #expect(
            mesh.submeshes == [
                PMX.Submesh(indexOffset: 0, indexCount: 6, materialIndex: 0),
                PMX.Submesh(indexOffset: 6, indexCount: 6, materialIndex: 1),
                PMX.Submesh(indexOffset: 12, indexCount: 6, materialIndex: 2),
            ])
    }

    @Test("mismatched or truncated material section yields no submeshes but geometry still reads")
    func toleratesUnreadableMaterials() throws {
        let verts: [SIMD3<Float>] = [
            .init(0, 0, 0), .init(1, 0, 0), .init(0, 1, 0), .init(1, 1, 0),
        ]

        // Surface counts don't sum to the index buffer length.
        let mismatched = Self.makePMX(vertices: verts, indices: [0, 1, 2, 1, 3, 2], materials: [3])
        let m1 = try PMX.read(data: mismatched)
        #expect(m1.triangleCount == 2)
        #expect(m1.submeshes.isEmpty)

        // Buffer cut off inside the material section.
        var truncated = Self.makePMX(vertices: verts, indices: [0, 1, 2])
        truncated.removeLast(8)
        let m2 = try PMX.read(data: truncated)
        #expect(m2.triangleCount == 1)
        #expect(m2.submeshes.isEmpty)
    }
}
