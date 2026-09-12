import Foundation

struct DrumxProjectedPoint: Equatable {
  let x: Double
  let y: Double
}

/// One planar homography for the entire playing surface. Lateral world positions
/// use -0.5...0.5 across the kit, and longitudinal positions use beats before NOW.
/// Its perspective factor is 1 / (1 + k * beatDistance). The same factor projects
/// road edges, beat rows, lane lines and every vertex of a timed note.
///
/// This is an explicit 2.5D plane, not a camera simulation or a separate scale
/// animation for each object. World dimensions never change as a note travels.
struct DrumxProjection {
  let centerX: Double
  let nearWidth: Double
  let topY: Double
  let strikeY: Double
  let previewBeats: Double
  let farScale: Double

  init(centerX: Double, nearWidth: Double, topY: Double, strikeY: Double,
       previewBeats: Double = 4, farScale: Double = 0.42) {
    precondition(centerX.isFinite && nearWidth.isFinite && nearWidth > 0)
    precondition(topY.isFinite && strikeY.isFinite && strikeY > topY)
    precondition(previewBeats.isFinite && previewBeats > 0)
    precondition(farScale.isFinite && farScale > 0 && farScale < 1)
    self.centerX = centerX
    self.nearWidth = nearWidth
    self.topY = topY
    self.strikeY = strikeY
    self.previewBeats = previewBeats
    self.farScale = farScale
  }

  var depthSlope: Double { (1 / farScale - 1) / previewBeats }
  var horizonY: Double { (topY - farScale * strikeY) / (1 - farScale) }

  static func beatDistance(eventTimeSeconds: Double, timelineSeconds: Double, bpm: Double) -> Double {
    precondition(eventTimeSeconds.isFinite && timelineSeconds.isFinite && bpm.isFinite && bpm > 0)
    // Signed timeline time is essential: during count-in, beat zero must still
    // approach the player. Clamping timelineSeconds to zero would freeze it at NOW.
    return (eventTimeSeconds - timelineSeconds) * bpm / 60
  }

  func project(lateral: Double, beatDistance: Double) -> DrumxProjectedPoint {
    let denominator = 1 + depthSlope * beatDistance
    precondition(lateral.isFinite && beatDistance.isFinite && denominator > 0)
    let factor = 1 / denominator
    return DrumxProjectedPoint(
      x: centerX + nearWidth * lateral * factor,
      y: horizonY + (strikeY - horizonY) * factor)
  }

  func width(at beatDistance: Double) -> Double {
    nearWidth / (1 + depthSlope * beatDistance)
  }

  func farVisibility(at beatDistance: Double) -> Double {
    let progress = min(1, max(0, (previewBeats - beatDistance) / min(0.7, previewBeats)))
    return progress * progress * (3 - 2 * progress)
  }

  func laneCenter(_ index: Int, laneCount: Int = 7) -> Double {
    precondition(laneCount > 0 && index >= 0 && index < laneCount)
    return -0.5 + (Double(index) + 0.5) / Double(laneCount)
  }

  func rectangle(centerLateral: Double, beatDistance: Double,
                 worldWidth: Double, worldDepth: Double) -> [DrumxProjectedPoint] {
    let halfWidth = worldWidth / 2, halfDepth = worldDepth / 2
    return [
      project(lateral: centerLateral - halfWidth, beatDistance: beatDistance + halfDepth),
      project(lateral: centerLateral + halfWidth, beatDistance: beatDistance + halfDepth),
      project(lateral: centerLateral + halfWidth, beatDistance: beatDistance - halfDepth),
      project(lateral: centerLateral - halfWidth, beatDistance: beatDistance - halfDepth),
    ]
  }

  func cymbal(centerLateral: Double, beatDistance: Double,
              worldWidth: Double, worldDepth: Double) -> [DrumxProjectedPoint] {
    let positions = [
      (-worldWidth / 2, 0.0), (-worldWidth * 0.29, worldDepth / 2),
      (worldWidth * 0.29, worldDepth / 2), (worldWidth / 2, 0.0),
      (worldWidth * 0.29, -worldDepth / 2), (-worldWidth * 0.29, -worldDepth / 2),
    ]
    return positions.map {
      project(lateral: centerLateral + $0.0, beatDistance: beatDistance + $0.1)
    }
  }

  func drum(centerLateral: Double, beatDistance: Double,
            worldWidth: Double, worldDepth: Double) -> [DrumxProjectedPoint] {
    // Rounded corners are sampled in world space before projection. A fixed
    // screen-space radius would detach their shape from the projected plane.
    let rx = worldWidth * 0.17, rz = worldDepth * 0.27
    let corners = [
      (worldWidth / 2 - rx, worldDepth / 2 - rz, 0.0),
      (-worldWidth / 2 + rx, worldDepth / 2 - rz, Double.pi / 2),
      (-worldWidth / 2 + rx, -worldDepth / 2 + rz, Double.pi),
      (worldWidth / 2 - rx, -worldDepth / 2 + rz, Double.pi * 1.5),
    ]
    return corners.flatMap { corner in
      (0...4).map { step in
        let angle = corner.2 + Double(step) * Double.pi / 8
        return project(
          lateral: centerLateral + corner.0 + cos(angle) * rx,
          beatDistance: beatDistance + corner.1 + sin(angle) * rz)
      }
    }
  }
}
