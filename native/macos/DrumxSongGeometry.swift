import Foundation

struct DrumxSongVertex {
  let x: Double
  let z: Double
  let height: Double
}

/// A pitched perspective camera extends the road's homography into height.
/// Height changes the perspective denominator as well as screen Y. A fixed
/// aspect local camera shapes each mesh; its visible center follows the shared
/// road timeline. Different shells cannot create different timing destinations.
enum DrumxSongGeometry {
  static let strikeHeight = 0.024
  static let pitch = Double.pi * 25 / 180

  static func project(_ vertex: DrumxSongVertex, with road: DrumxProjection) -> DrumxProjectedPoint {
    let denominator = 1 + road.depthSlope * vertex.z
      - road.depthSlope * tan(pitch) * vertex.height
    precondition(denominator > 0)
    return DrumxProjectedPoint(
      x: road.centerX + road.nearWidth * vertex.x / denominator,
      y: road.horizonY + (road.strikeY - road.horizonY
        - road.nearWidth * vertex.height / cos(pitch)) / denominator)
  }

  static func center(pad: Int, distance: Double, road: DrumxProjection) -> DrumxProjectedPoint {
    let hands = [0, 6, 1, 3, 4, 5, 7]
    let lateral = pad == 2 ? 0 : road.laneCenter(hands.firstIndex(of: pad)!)
    return road.project(lateral: lateral, beatDistance: distance)
  }

  /// Readable note faces use the same local camera orientation in every lane.
  /// Their centers still follow the highway perspective. This avoids turning
  /// the outer catchers into diagonally tilted targets with a different apparent
  /// hit row, while retaining projected height, bevel depth and contact shadows.
  static func projectFace(_ vertex: DrumxSongVertex, pad: Int, distance: Double,
                          road: DrumxProjection) -> DrumxProjectedPoint {
    let hands = [0, 6, 1, 3, 4, 5, 7]
    let lateral = pad == 2 ? 0 : road.laneCenter(hands.firstIndex(of: pad)!)
    let anchor = center(pad: pad, distance: distance, road: road)
    // A fixed aspect camera shapes the mesh. The timeline can become longer in
    // fullscreen without changing a drum into a tall oval or changing its tilt.
    let meshCamera = DrumxProjection(centerX: 0, nearWidth: road.nearWidth,
      topY: -road.nearWidth * 0.70, strikeY: 0,
      previewBeats: road.previewBeats, farScale: road.farScale)
    let local = project(DrumxSongVertex(x: vertex.x - lateral, z: vertex.z, height: vertex.height), with: meshCamera)
    let crest = project(DrumxSongVertex(x: 0, z: distance, height: strikeHeight), with: meshCamera)
    return DrumxProjectedPoint(x: anchor.x + local.x, y: anchor.y + local.y - crest.y)
  }

  static func alignmentOffset(rings: [[DrumxSongVertex]], pad: Int,
                              distance: Double, road: DrumxProjection) -> Double {
    let ys = rings.flatMap { $0 }.map { projectFace($0, pad: pad, distance: distance, road: road).y }
    guard let first = ys.min(), let last = ys.max() else { return 0 }
    return center(pad: pad, distance: distance, road: road).y - (first + last) / 2
  }

  /// Cross sections define actual shells and bevels in world units. Broad
  /// drums have domed caps; thinner cymbals rise to a small central bell.
  static func rings(pad: Int, distance: Double, road: DrumxProjection,
                    catcher: Bool = false) -> [[DrumxSongVertex]] {
    let hands = [0, 6, 1, 3, 4, 5, 7]
    let lateral = pad == 2 ? 0 : road.laneCenter(hands.firstIndex(of: pad)!)
    let width = (catcher ? 0.83 : 0.71) / 7
    let depth = catcher ? 0.12 : 0.10
    let cymbal = [0, 6, 7].contains(pad)
    let sections: [(Double, Double)]
    if pad == 2 {
      sections = [(1, 0.014), (1, 0.020), (0.985, strikeHeight)]
    } else if catcher {
      sections = [(1, 0), (1, 0.010), (0.94, strikeHeight), (0.77, strikeHeight)]
    } else if cymbal {
      sections = [(1, 0.004), (1, 0.009), (0.78, 0.014), (0.30, strikeHeight)]
    } else {
      sections = [(1, 0), (1, 0.009), (0.91, 0.019), (0.69, strikeHeight)]
    }
    return sections.map { scale, elevation in
      if pad == 2 {
        let halfDepth = 0.024 * scale
        return [(-0.495 * scale, halfDepth), (0.495 * scale, halfDepth),
                (0.495 * scale, -halfDepth), (-0.495 * scale, -halfDepth)].map {
          DrumxSongVertex(x: $0.0, z: distance + $0.1, height: elevation)
        }
      }
      return (0..<72).map { index in
        let angle = Double(index) * 2 * Double.pi / 72
        // A soft squared drum shell and a circular cymbal silhouette are easy
        // to distinguish without changing their shared timing center.
        let c = cos(angle), s = sin(angle), exponent = cymbal ? 1.0 : 0.60
        let x = (c < 0 ? -1.0 : 1.0) * pow(abs(c), exponent)
        let z = (s < 0 ? -1.0 : 1.0) * pow(abs(s), exponent)
        return DrumxSongVertex(x: lateral + x * width * scale / 2,
          z: distance + z * depth * scale / 2, height: elevation)
      }
    }
  }

  /// Directional diffuse lighting for a surface in world coordinates.
  static func light(_ vertices: [DrumxSongVertex]) -> Double {
    guard vertices.count >= 3 else { return 0.6 }
    let a = vertices[0], b = vertices[1], c = vertices[2]
    let ux = b.x - a.x, uy = b.height - a.height, uz = b.z - a.z
    let vx = c.x - a.x, vy = c.height - a.height, vz = c.z - a.z
    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx
    let length = sqrt(nx * nx + ny * ny + nz * nz)
    guard length > 0.0000001 else { return 0.6 }
    // Rings wind clockwise from above, so invert their normal toward the shell.
    let diffuse = max(0, (-nx * -0.38 - ny * 0.82 - nz * -0.43) / length)
    return min(1, 0.22 + diffuse * 0.78)
  }
}
