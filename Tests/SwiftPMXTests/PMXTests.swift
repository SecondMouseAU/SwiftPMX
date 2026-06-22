import Testing
import Foundation
@testable import SwiftPMX

@Suite("PMX reading")
struct PMXTests {

    /// Build a valid PMX 2.0 byte buffer: the given vertices + triangle index list. Encoding UTF-8,
    /// all index widths 1 byte, no additional UVs, BDEF1 skinning.
    static func makePMX(vertices: [SIMD3<Float>], indices: [UInt8], version: Float = 2.0) -> Data {
        var d = Data()
        func u8(_ v: UInt8) { d.append(v) }
        func i32(_ v: Int32) { var x = v; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func f32(_ v: Float) { var x = v; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }

        d.append(contentsOf: [0x50, 0x4D, 0x58, 0x20])        // "PMX "
        f32(version)
        u8(8)                                                 // setting count
        u8(1)                                                 // encoding = UTF-8
        u8(0)                                                 // additional UV = 0
        for _ in 0..<6 { u8(1) }                              // index sizes = 1
        for _ in 0..<4 { i32(0) }                             // 4 empty model-info strings

        i32(Int32(vertices.count))
        for v in vertices {
            f32(v.x); f32(v.y); f32(v.z)                      // position
            f32(0); f32(0); f32(0)                            // normal
            f32(0); f32(0)                                    // uv
            u8(0)                                             // skinning type BDEF1
            u8(0)                                             // bone index (1 byte)
            f32(0)                                            // edge scale
        }

        i32(Int32(indices.count))
        d.append(contentsOf: indices)
        return d
    }

    @Test("reads geometry, negates Z, reverses winding, culls degenerate")
    func readsGeometry() throws {
        let verts: [SIMD3<Float>] = [.init(0, 0, 0), .init(1, 0, 0), .init(0, 1, 0), .init(1, 1, 3)]
        let mesh = try PMX.read(data: Self.makePMX(vertices: verts, indices: [0, 1, 2, 1, 3, 2, 0, 0, 1]))

        #expect(mesh.vertexCount == 4)
        #expect(mesh.triangleCount == 2)              // degenerate (0,0,1) dropped
        let b = try #require(mesh.bounds)
        #expect(abs(b.min.z - (-3)) < 1e-5)           // Z negated
        #expect(abs(b.max.z - 0) < 1e-5)
    }

    @Test("convertToRightHanded:false keeps native MMD Z")
    func keepsNativeFrame() throws {
        let verts: [SIMD3<Float>] = [.init(0, 0, 0), .init(1, 0, 0), .init(0, 0, 5)]
        var opts = PMX.Options(); opts.convertToRightHanded = false
        let mesh = try PMX.read(data: Self.makePMX(vertices: verts, indices: [0, 1, 2]), options: opts)
        let b = try #require(mesh.bounds)
        #expect(abs(b.max.z - 5) < 1e-5)              // not negated
    }

    @Test("scale multiplies coordinates")
    func appliesScale() throws {
        let verts: [SIMD3<Float>] = [.init(0, 0, 0), .init(1, 0, 0), .init(0, 2, 0)]
        var opts = PMX.Options(); opts.scale = 10
        let mesh = try PMX.read(data: Self.makePMX(vertices: verts, indices: [0, 1, 2]), options: opts)
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
        #expect(try PMX.read(data: data).vertexCount == 4)                 // welded

        var raw = PMX.Options(); raw.weldEpsilon = nil
        #expect(try PMX.read(data: data, options: raw).vertexCount == 6)   // unwelded soup
    }

    @Test("rejects bad magic and bad version")
    func rejects() {
        var bad = Data([0x46, 0x4F, 0x4F, 0x20]); bad.append(Data(count: 32))
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
}
