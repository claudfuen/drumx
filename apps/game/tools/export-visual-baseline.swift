// Emit the original Mac projection as a portable visual geometry contract.
// swiftc native/macos/DrumxProjection.swift apps/game/tools/export-visual-baseline.swift -o .build/export-visual-baseline
// .build/export-visual-baseline > apps/game/data/visual-baseline.json
import Foundation

@main enum ExportVisualBaseline {
  static func coordinates(_ points: [DrumxProjectedPoint]) -> [[Double]] {
    points.map { [$0.x, $0.y] }
  }
  static func main() throws {
    var cases: [[String: Any]] = []
    for (width, height) in [(1020.0, 640.0), (1140, 710), (1440, 780), (1920, 960), (2560, 1320)] {
      let projection = DrumxProjection(centerX: width / 2, nearWidth: min(870, width - 132),
        topY: 55, strikeY: max(215, height - 193))
      var points: [[String: Any]] = []
      var notes: [[String: Any]] = []
      for beat in [0.0, 0.25, 1, 2, 3, 3.5, 4] {
        for lateral in [-0.5, projection.laneCenter(0), projection.laneCenter(2), 0, 0.5] {
          let point = projection.project(lateral: lateral, beatDistance: beat)
          points.append(["lateral": lateral, "beat": beat, "point": [point.x, point.y]])
        }
        for pad in 0..<3 {
          let lateral = pad == 2 ? 0 : projection.laneCenter(pad == 0 ? 0 : 2)
          let shape = pad == 2
            ? projection.rectangle(centerLateral: 0, beatDistance: beat, worldWidth: 0.99, worldDepth: 0.04)
            : pad == 0
              ? projection.cymbal(centerLateral: lateral, beatDistance: beat, worldWidth: 0.66 / 7, worldDepth: 0.12)
              : projection.drum(centerLateral: lateral, beatDistance: beat, worldWidth: 0.66 / 7, worldDepth: 0.12)
          notes.append(["pad": pad, "beat": beat, "vertices": coordinates(shape),
                        "opacity": projection.farVisibility(at: beat)])
        }
      }
      cases.append(["size": [width, height], "points": points, "notes": notes])
    }
    let baseline: [String: Any] = ["version": 1, "units": "logical points",
      "source": "native/macos/DrumxProjection.swift and PracticeView.swift",
      "preview_beats": 4, "far_scale": 0.42,
      "slots": ["hi-hat", "crash", "snare", "tom 1", "tom 2", "floor tom", "ride"],
      "cases": cases]
    let data = try JSONSerialization.data(withJSONObject: baseline,
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
  }
}
