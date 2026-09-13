import Foundation

struct DrumxSongTempo: Decodable, Equatable {
  let tick: Double
  let timeSeconds: Double
  let bpm: Double
}

struct DrumxSongTimeSignature: Decodable, Equatable {
  let tick: Double
  let numerator: Int
  let denominator: Int
}

enum DrumxSongGridKind: Equatable {
  case bar
  case beat
  case subdivision
}

struct DrumxSongGridLine: Equatable {
  let time: Double
  let kind: DrumxSongGridKind
}

/// Musical grid preparation happens once per song start. The renderer only
/// projects these audio-clock positions, just as it projects chart notes.
enum DrumxSongGrid {
  static let maximumLineCount = 250_000

  static func lines(resolution: Int, tempos: [DrumxSongTempo],
                    signatures: [DrumxSongTimeSignature], lead: Double,
                    duration: Double) -> [DrumxSongGridLine] {
    guard resolution > 0, resolution <= 32767, lead.isFinite, lead >= 0,
      duration.isFinite, duration > 0 else { return [] }
    var tempoByTick: [Double: DrumxSongTempo] = [:]
    for tempo in tempos {
      guard tempo.tick.isFinite, tempo.tick >= 0, tempo.timeSeconds.isFinite,
        tempo.bpm.isFinite, tempo.bpm > 0, tempo.bpm <= 10000 else { return [] }
      tempoByTick[tempo.tick] = tempo
    }
    let tempoMap = tempoByTick.values.sorted { $0.tick < $1.tick }
    // Missing clocks cannot honestly supply musical lines. Imported charts
    // include tick zero, even when their source relied on MIDI's default tempo.
    guard tempoMap.first?.tick == 0 else { return [] }
    for index in tempoMap.indices.dropFirst() {
      let previous = tempoMap[index - 1], current = tempoMap[index]
      let expected = previous.timeSeconds + (current.tick - previous.tick) * 60 / (Double(resolution) * previous.bpm)
      guard current.timeSeconds > previous.timeSeconds,
        abs(current.timeSeconds - expected) < 0.000001 else { return [] }
    }

    var meters: [Double: DrumxSongTimeSignature] = [0:
      DrumxSongTimeSignature(tick: 0, numerator: 4, denominator: 4)]
    for signature in signatures {
      guard signature.tick.isFinite, signature.tick >= 0,
        (1...255).contains(signature.numerator), (1...128).contains(signature.denominator),
        signature.denominator.nonzeroBitCount == 1 else { return [] }
      meters[signature.tick] = signature
    }
    let meterMap = meters.values.sorted { $0.tick < $1.tick }
    let endTime = min(duration, 7200)
    var firstTempoIndex = 0
    while firstTempoIndex + 1 < tempoMap.count && tempoMap[firstTempoIndex + 1].timeSeconds <= -lead {
      firstTempoIndex += 1
    }
    let firstTempo = tempoMap[firstTempoIndex]
    let firstVisibleTick = max(0, firstTempo.tick + (-lead - firstTempo.timeSeconds)
      * Double(resolution) * firstTempo.bpm / 60)
    guard firstVisibleTick.isFinite else { return [] }
    var result: [DrumxSongGridLine] = []
    var tempoIndex = 0
    for (meterIndex, meter) in meterMap.enumerated() {
      let endTick = meterIndex + 1 < meterMap.count ? meterMap[meterIndex + 1].tick : Double.infinity
      let unitTicks = Double(resolution) * 4 / Double(meter.denominator)
      let compound = meter.denominator >= 8 && meter.numerator >= 6 && meter.numerator % 3 == 0
      let firstUnit = max(0, ceil((firstVisibleTick - meter.tick) / unitTicks - 0.000000001))
      guard firstUnit.isFinite, firstUnit < Double(Int.max / 2) else { return [] }
      var unit = Int(firstUnit)
      var iterations = 0
      while true {
        let tick = meter.tick + Double(unit) * unitTicks
        // A signature event starts its own bar, even when it interrupts an old
        // bar. Tempo events change spacing without resetting musical position.
        if tick >= endTick { break }
        while tempoIndex + 1 < tempoMap.count && tempoMap[tempoIndex + 1].tick <= tick {
          tempoIndex += 1
        }
        let tempo = tempoMap[tempoIndex]
        let time = tempo.timeSeconds + (tick - tempo.tick) * 60 / (Double(resolution) * tempo.bpm) + lead
        guard time.isFinite else { return [] }
        if time > endTime + 0.000000001 { return result }
        if time >= -0.000000001 {
          let kind: DrumxSongGridKind = unit % meter.numerator == 0 ? .bar
            : compound && unit % 3 != 0 ? .subdivision : .beat
          result.append(DrumxSongGridLine(time: max(0, time), kind: kind))
          if result.count >= maximumLineCount { return result }
        }
        unit += 1
        iterations += 1
        if iterations >= maximumLineCount { return result }
      }
    }
    return result
  }
}
