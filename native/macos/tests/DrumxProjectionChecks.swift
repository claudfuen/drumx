import Foundation

@main enum DrumxProjectionChecks {
  static func main() {
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ label: String) {
      checks += 1
      guard condition() else { fatalError("Projection check failed: \(label)") }
    }
    func near(_ a: Double, _ b: Double, tolerance: Double = 0.0000001) -> Bool {
      abs(a - b) <= tolerance
    }
    for height in [470.0, 550.0, 650.0] {
      let p = DrumxProjection(centerX: 540, nearWidth: 870, topY: 55,
                              strikeY: height - 193)
      check(near(p.project(lateral: 0, beatDistance: 0).y, p.strikeY), "NOW is beat zero")
      check(near(p.project(lateral: 0, beatDistance: 4).y, p.topY), "Preview reaches top")
      check(near(p.width(at: 0), p.nearWidth), "Near road width")
      check(near(p.width(at: 4), p.nearWidth * p.farScale), "Far road width")
      check(p.farVisibility(at: 4) == 0 && p.farVisibility(at: 4.1) == 0,
            "Notes enter the far plane invisibly")
      check(near(p.farVisibility(at: 3.3), 1) && p.farVisibility(at: 0) == 1,
            "Far fade ends without changing the near playing surface")
      check(p.farVisibility(at: 3.9) < p.farVisibility(at: 3.7)
            && p.farVisibility(at: 3.7) < p.farVisibility(at: 3.4),
            "Distance fade grows smoothly while approaching")
      for step in 0...80 {
        let beat = Double(step) / 20
        let rowY = p.project(lateral: 0, beatDistance: beat).y
        let left = p.project(lateral: -0.5, beatDistance: beat)
        let right = p.project(lateral: 0.5, beatDistance: beat)
        check(near(right.x - left.x, p.width(at: beat)), "Road uses projected width")
        check(left.y == rowY && right.y == rowY, "Whole beat row is horizontal")
        for slot in 0..<7 {
          let lateral = p.laneCenter(slot)
          let center = p.project(lateral: lateral, beatDistance: beat)
          check(center.y == rowY, "All instrument centers share exact time row")
          let quad = p.rectangle(centerLateral: lateral, beatDistance: beat,
                                 worldWidth: 0.66 / 7, worldDepth: 0.12)
          check(quad[0].y == quad[1].y && quad[2].y == quad[3].y,
                "Note far and near edges stay on projected beat rows")
          check(near((quad[1].x - quad[0].x) / p.width(at: beat + 0.06), 0.66 / 7),
                "Far note edge and road use the identical transform")
          check(near((quad[2].x - quad[3].x) / p.width(at: beat - 0.06), 0.66 / 7),
                "Near note edge and road use the identical transform")
          check(quad[0].y < quad[3].y, "Plane note retains positive depth")
          let rayNear = p.project(lateral: lateral, beatDistance: 0)
          let rayFar = p.project(lateral: lateral, beatDistance: 4)
          let cross = (center.x - rayNear.x) * (rayFar.y - rayNear.y)
            - (center.y - rayNear.y) * (rayFar.x - rayNear.x)
          check(abs(cross) < 0.000001, "Lane center remains on its straight rail")
          check(p.cymbal(centerLateral: lateral, beatDistance: beat,
                          worldWidth: 0.66 / 7, worldDepth: 0.12).count == 6,
                "Cymbal vertices use fixed world geometry")
          check(p.drum(centerLateral: lateral, beatDistance: beat,
                        worldWidth: 0.66 / 7, worldDepth: 0.12).count == 20,
                "Drum corners use fixed world geometry")
        }
        if step > 0 {
          check(p.project(lateral: 0, beatDistance: beat - 0.05).y > rowY,
                "Approaching notes move monotonically toward NOW")
          check(p.width(at: beat - 0.05) > p.width(at: beat),
                "Approaching width grows monotonically")
        }
      }
      let kick = p.rectangle(centerLateral: 0, beatDistance: 1.5,
                             worldWidth: 0.99, worldDepth: 0.04)
      check(near((kick[1].x - kick[0].x) / p.width(at: 1.52), 0.99),
            "Kick far edge obeys the road transform")
      check(near((kick[2].x - kick[3].x) / p.width(at: 1.48), 0.99),
            "Kick near edge obeys the road transform")
      check(p.project(lateral: 0, beatDistance: -0.01).y > p.strikeY,
            "Notes continue through NOW without clamping their centers")
      for bpm in [48.0, 96.0, 144.0] {
        let countStart = DrumxProjection.beatDistance(eventTimeSeconds: 0,
                                                     timelineSeconds: -240 / bpm, bpm: bpm)
        let countMiddle = DrumxProjection.beatDistance(eventTimeSeconds: 0,
                                                      timelineSeconds: -120 / bpm, bpm: bpm)
        let firstBeat = DrumxProjection.beatDistance(eventTimeSeconds: 0, timelineSeconds: 0, bpm: bpm)
        check(near(countStart, 4), "First note is four beats away at count-in start")
        check(near(p.project(lateral: 0, beatDistance: countStart).y, p.topY),
              "First note enters at the far row when count-in begins")
        let middleY = p.project(lateral: 0, beatDistance: countMiddle).y
        check(middleY > p.topY && middleY < p.strikeY, "Opening note travels during count-in")
        check(firstBeat == 0 && near(p.project(lateral: 0, beatDistance: firstBeat).y, p.strikeY),
              "Opening note reaches NOW exactly at practiceStart")
        let before = DrumxProjection.beatDistance(eventTimeSeconds: 0, timelineSeconds: -0.00001, bpm: bpm)
        let after = DrumxProjection.beatDistance(eventTimeSeconds: 0, timelineSeconds: 0.00001, bpm: bpm)
        let beforeY = p.project(lateral: 0, beatDistance: before).y
        let afterY = p.project(lateral: 0, beatDistance: after).y
        check(beforeY < p.strikeY && afterY > p.strikeY && afterY - beforeY < 0.1,
              "Crossing practiceStart is continuous with no clamp or jump")
      }
    }
    print("Projection checks passed: \(checks)")
  }
}
