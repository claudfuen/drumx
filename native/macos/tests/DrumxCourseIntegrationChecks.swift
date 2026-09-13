import Foundation
import AVFoundation

private var checks = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError("FAIL: \(message)") }
}

private func near(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
    abs(a - b) <= tolerance
}

/// Short, distinct pad impulses make additional or misplaced audible notes
/// observable without an audio device or assumptions about acoustic transients.
private func impulseBank() throws -> DrumxSampleBank {
    let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 2)!
    let entries = (0..<3).map {
        DrumxSampleEntry(pad: $0, velocityMin: 1, velocityMax: 127, roundRobin: 0,
                         file: "integration-impulse-\($0)")
    }
    let buffers = (0..<3).map { pad in
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8)!
        buffer.frameLength = 8
        for channel in 0..<2 {
            buffer.floatChannelData![channel].update(repeating: 0, count: 8)
            buffer.floatChannelData![channel][0] = Float(1 << pad) / 10
        }
        return buffer
    }
    return DrumxSampleBank(selector: try DrumxSampleSelector(entries: entries),
                           buffers: buffers, format: format)
}

private func checkLesson(_ lesson: DrumxLessonDefinition, realBank: DrumxSampleBank,
                          impulses: DrumxSampleBank) throws {
    let bars = 4
    let durationBeats = Double(bars * 4)
    let secondsPerBeat = 60 / lesson.suggestedBPM
    let authored = (0..<bars).flatMap { bar in
        lesson.events.map {
            DrumxDemoHit(pad: $0.pad, beat: Double(bar * 4) + $0.beat, velocity: $0.velocity)
        }
    }
    let chart = authored.map { DXChartEvent(pad: Int32($0.pad), beat: $0.beat) }
    guard let core = dx_core_create() else { fatalError("Cannot allocate scoring core") }
    defer { dx_core_destroy(core) }
    let loaded = chart.withUnsafeBufferPointer {
        dx_core_load_chart(core, lesson.suggestedBPM, durationBeats, $0.baseAddress, Int32($0.count))
    }
    check(loaded == 1, "\(lesson.id): authored chart accepted by scoring core")
    check(Int(dx_core_event_count(core)) == authored.count,
          "\(lesson.id): no built-in groove targets injected")
    let durationSeconds = durationBeats * secondsPerBeat
    check(near(dx_core_duration(core), durationSeconds), "\(lesson.id): scored phrase duration")

    var scoredPads = Set<Int>()
    for (index, note) in authored.enumerated() {
        var target = DXEvent()
        check(dx_core_event(core, Int32(index), &target) == 1,
              "\(lesson.id): authored event is accessible")
        check(Int(target.id) == index && Int(target.pad) == note.pad
            && near(target.time_seconds, note.beat * secondsPerBeat),
              "\(lesson.id): core target order and song time agree with authorship")
        scoredPads.insert(Int(target.pad))
        let hit = dx_core_input(core, Int32(note.pad), note.beat * secondsPerBeat,
                                 Double(note.velocity) / 127)
        check(hit.judgment == DX_CENTERED.rawValue && Int(hit.event_id) == index,
              "\(lesson.id): perfect authored replay matches its own target")
    }
    dx_core_advance(core, durationSeconds)
    var result = DXSnapshot()
    dx_core_snapshot(core, &result)
    check(result.finished == 1 && Int(result.total.expected) == authored.count
        && Int(result.total.matched) == authored.count && Int(result.total.on_time) == authored.count
        && result.total.missed == 0 && result.total.extra == 0
        && Int(result.total.best_streak) == authored.count
        && near(result.total.timing_accuracy_percent, 100),
          "\(lesson.id): complete perfect replay has honest full score")

    // Reverse input ensures the demo shares core's deterministic authoring order.
    let rendered = try DrumxDemoAudio.render(bank: realBank, bpm: lesson.suggestedBPM,
                                             durationBeats: durationBeats, hits: authored.reversed())
    check(rendered.hits == authored, "\(lesson.id): real demo keeps every authored pad, beat and velocity")
    check(Set(rendered.hits.map(\.pad)) == scoredPads,
          "\(lesson.id): sparse demo and grading use only the authored instruments")
    let rate = realBank.format.sampleRate
    var expectedFrames = Int(ceil(durationSeconds * rate))
    var selector = realBank.selector
    for hit in authored {
        guard let sample = selector.select(pad: hit.pad, velocity: hit.velocity) else {
            fatalError("Authored velocity has no recorded sample: \(lesson.id)")
        }
        let startFrame = Int((hit.beat * rate * secondsPerBeat).rounded())
        expectedFrames = max(expectedFrames, startFrame + Int(realBank.buffers[sample].frameLength))
    }
    check(Int(rendered.buffer.frameLength) == expectedFrames
        && near(rendered.durationSeconds, Double(expectedFrames) / rate),
          "\(lesson.id): demo lasts for the same phrase plus exactly the recorded sample tails")
    check(rendered.durationSeconds >= dx_core_duration(core),
          "\(lesson.id): sample playback cannot truncate the authored phrase")
    let realFrames = Int(rendered.buffer.frameLength)
    for channel in 0..<Int(rendered.buffer.format.channelCount) {
        let values = UnsafeBufferPointer(start: rendered.buffer.floatChannelData![channel], count: realFrames)
        check(values.allSatisfy { $0.isFinite && abs($0) <= 0.981 },
              "\(lesson.id): decoded acoustic mix is finite and keeps headroom")
        check(values.contains { abs($0) > 0.001 }, "\(lesson.id): real acoustic rendering is audible PCM")
    }

    let precise = try DrumxDemoAudio.render(bank: impulses, bpm: lesson.suggestedBPM,
                                            durationBeats: durationBeats, hits: authored)
    let framesPerBeat = impulses.format.sampleRate * secondsPerBeat
    let phraseFrames = Int(ceil(durationBeats * framesPerBeat))
    check(Int(precise.buffer.frameLength) == phraseFrames,
          "\(lesson.id): short samples do not lengthen the phrase")
    var expectedOnsets: [Int: Float] = [:]
    for hit in authored {
        let frame = Int((hit.beat * framesPerBeat).rounded())
        expectedOnsets[frame, default: 0] += Float(1 << hit.pad) / 10
    }
    for channel in 0..<Int(precise.buffer.format.channelCount) {
        let pcm = precise.buffer.floatChannelData![channel]
        var correct = true
        for frame in 0..<phraseFrames {
            if abs(pcm[frame] - (expectedOnsets[frame] ?? 0)) > 0.00001 {
                correct = false
                break
            }
        }
        check(correct, "\(lesson.id): all sample-frame attacks, chords and rests match the authored chart")
    }
}

private func invalidDemoChecks(_ bank: DrumxSampleBank) throws {
    let valid = [DrumxDemoHit(pad: 1, beat: 1, velocity: 100)]
    func rejects(_ bpm: Double = 60, _ duration: Double = 4,
                 _ hits: [DrumxDemoHit] = valid, _ message: String) {
        do {
            _ = try DrumxDemoAudio.render(bank: bank, bpm: bpm, durationBeats: duration, hits: hits)
            check(false, message)
        } catch is DrumxSamplerError {
            check(true, message)
        } catch {
            check(false, "\(message): expected a validation error, got \(error)")
        }
    }
    for bpm in [Double.nan, .infinity, -.infinity, 0, 19.99, 400.01] {
        rejects(bpm, 4, valid, "invalid demo BPM is rejected before rendering")
    }
    for duration in [Double.nan, .infinity, -.infinity, 0, -1, 64.01] {
        rejects(60, duration, valid, "invalid demo duration is rejected before allocation")
    }
    for beat in [Double.nan, .infinity, -.infinity, -0.001, 4, 4.001] {
        rejects(60, 4, [DrumxDemoHit(pad: 1, beat: beat, velocity: 100)],
                "nonfinite or out-of-phrase demo event is rejected")
    }
    for pad in [-1, 3, Int.max] {
        rejects(60, 4, [DrumxDemoHit(pad: pad, beat: 0, velocity: 100)],
                "unsupported demo instrument is rejected")
    }
    for velocity in [Int.min, -1, 0, 128, Int.max] {
        rejects(60, 4, [DrumxDemoHit(pad: 1, beat: 0, velocity: velocity)],
                "invalid demo velocity is rejected instead of producing a silent note")
    }
    rejects(60, 4, [], "empty demo chart is rejected")
    rejects(60, 4, Array(repeating: valid[0], count: 1025), "oversized demo chart is rejected")
    let after = try DrumxDemoAudio.render(bank: bank, bpm: 60, durationBeats: 4, hits: valid)
    check(after.hits == valid && after.durationSeconds >= 4,
          "rejected demos leave the loaded bank usable for the next lesson")
}

@main
private struct DrumxCourseIntegrationChecks {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Usage: course-integration-checks /path/to/BigRusty/manifest.json")
        }
        let manifest = URL(fileURLWithPath: CommandLine.arguments[1])
        let bank = try DrumxSampleBank.load(manifestURL: manifest, sampleRate: 8_000)
        check(bank.buffers.count == 80, "full acoustic kit decodes all velocity layers and alternates")
        check(DrumxCourse.lessons.count == 20, "all twenty authored lessons are exercised")
        let impulses = try impulseBank()
        for lesson in DrumxCourse.lessons {
            try checkLesson(lesson, realBank: bank, impulses: impulses)
        }
        try invalidDemoChecks(bank)
        print("Drumx course integration: \(checks) checks passed across \(DrumxCourse.lessons.count) lessons, with no audio device started.")
    }
}
