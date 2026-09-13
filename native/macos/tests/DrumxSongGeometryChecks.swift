import Foundation

@main enum DrumxSongGeometryChecks {
  static func main() {
    var count = 0
    func check(_ value: Bool, _ message: String) {
      count += 1
      precondition(value, message)
    }
    for width in [440.0, 560, 650] {
      let road = DrumxProjection(centerX: 500, nearWidth: width, topY: 56,
        strikeY: 470, previewBeats: 5.4, farScale: 0.28)
      for distance in [-0.02, 0, 0.5, 2, 5.4] {
        let targetY = DrumxSongGeometry.center(pad: 2, distance: distance, road: road).y
        for pad in 0..<8 {
          let center = DrumxSongGeometry.center(pad: pad, distance: distance, road: road)
          check(abs(center.y - targetY) < 0.000001, "All eight raised crests share a timing row")
          let rings = DrumxSongGeometry.rings(pad: pad, distance: distance, road: road)
          let alignment = DrumxSongGeometry.alignmentOffset(rings: rings, pad: pad, distance: distance, road: road)
          let visibleY = rings.flatMap { $0 }.map {
            DrumxSongGeometry.projectFace($0, pad: pad, distance: distance, road: road).y + alignment
          }
          check(abs((visibleY.min()! + visibleY.max()!) / 2 - targetY) < 0.000001,
            "Visible cymbal, drum and kick centers share the exact timing row")
          check(rings.allSatisfy { $0.count == rings[0].count }, "Rings connect without missing faces")
          check(rings.last!.allSatisfy { $0.height == DrumxSongGeometry.strikeHeight }, "Crests share physical elevation")
          check(rings.flatMap { $0 }.allSatisfy {
            let point = DrumxSongGeometry.project($0, with: road)
            return point.x.isFinite && point.y.isFinite
          }, "Every body vertex projects finitely across the visible highway")
          let catcher = DrumxSongGeometry.rings(pad: pad, distance: 0, road: road, catcher: true)
          check(catcher.last![0].height == rings.last![0].height, "Targets and notes meet at the same height")
          let closer = DrumxSongGeometry.center(pad: pad, distance: distance - 0.001, road: road)
          check(closer.y > center.y, "Notes cross NOW continuously toward the player")
        }
        for lateral in [-0.4, 0, 0.4] {
          let ground = road.project(lateral: lateral, beatDistance: distance)
          let projected = DrumxSongGeometry.project(DrumxSongVertex(x: lateral, z: distance, height: 0), with: road)
          check(abs(ground.x - projected.x) < 0.000001 && abs(ground.y - projected.y) < 0.000001,
            "3D ground is exactly the road homography")
          let raised = DrumxSongGeometry.project(DrumxSongVertex(x: lateral, z: distance, height: 0.024), with: road)
          check(raised.y < ground.y, "Physical height rises above the road")
          if lateral != 0 {
            check(abs(raised.x - road.centerX) > abs(ground.x - road.centerX), "Height includes lateral perspective, not a vertical screen offset")
          }
        }
      }
    }
    for pad in 0..<8 {
      let compact = DrumxProjection(centerX: 500, nearWidth: 650, topY: 56,
        strikeY: 470, previewBeats: 5.4, farScale: 0.28)
      let fullscreen = DrumxProjection(centerX: 900, nearWidth: 650, topY: 56,
        strikeY: 1100, previewBeats: 5.4, farScale: 0.28)
      for distance in [0.0, 1, 4] {
        let compactCenter = DrumxSongGeometry.center(pad: pad, distance: distance, road: compact)
        let fullscreenCenter = DrumxSongGeometry.center(pad: pad, distance: distance, road: fullscreen)
        let mesh = DrumxSongGeometry.rings(pad: pad, distance: distance, road: compact)
        for vertex in mesh.flatMap({ $0 }) {
          let small = DrumxSongGeometry.projectFace(vertex, pad: pad, distance: distance, road: compact)
          let large = DrumxSongGeometry.projectFace(vertex, pad: pad, distance: distance, road: fullscreen)
          check(abs((small.x - compactCenter.x) - (large.x - fullscreenCenter.x)) < 0.000001,
            "Fullscreen keeps mesh width and lateral pose")
          check(abs((small.y - compactCenter.y) - (large.y - fullscreenCenter.y)) < 0.000001,
            "A longer fullscreen highway cannot stretch or tilt the mesh")
        }
      }
    }
    print("Song geometry checks passed: \(count)")
  }
}
