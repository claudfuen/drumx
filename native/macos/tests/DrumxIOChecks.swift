import Foundation
import CoreMIDI
import Darwin

@main
struct Checks {
    static func main() throws {
        setbuf(stdout, nil)
        var events: [(Int, Int, Double, Bool)] = []
        let parser = MIDIByteStreamParser()
        func feed(_ bytes: [UInt8], _ time: Double, _ fallback: Bool = false) {
            bytes.withUnsafeBufferPointer {
                parser.consume(bytes: $0.baseAddress!, count: $0.count, hostSeconds: time,
                               usesArrival: fallback) { events.append(($0, $1, $2, $3)) }
            }
        }
        feed([0x99, 36, 100, 42, 80, 0xF8, 38, 0], 1)
        feed([0x89, 36, 64, 0x99, 38], 2)
        feed([110, 0xF8, 0xB9, 4, 127, 0x99, 46, 70], 3)
        feed([0xF0, 0x01, 0x02, 0xF8, 0x03, 0xF7, 0x99, 49, 90], 4, true)
        feed([0xF2, 2, 3, 40, 110, 0x99, 51, 100], 5)
        precondition(events.map { $0.0 } == [36, 42, 38, 46, 49, 51])
        precondition(events.map { $0.2 } == [1, 1, 2, 3, 4, 5])
        precondition(events[4].3)
        print("PASS byte parser: running status, packet splits, realtime, SysEx, system common, note-off filtering, fallback provenance")

        var client = MIDIClientRef()
        var source = MIDIEndpointRef()
        precondition(MIDIClientCreate("Drumx I/O Check" as CFString, nil, nil, &client) == noErr)
        precondition(MIDISourceCreate(client, "Drumx Check Source" as CFString, &source) == noErr)
        defer { MIDIEndpointDispose(source); MIDIClientDispose(client) }
        var sourceID: Int32 = 0
        precondition(MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &sourceID) == noErr)

        let io = DrumxIO()
        precondition(io.sources.contains(where: { $0.id == sourceID }))
        io.connect(sourceID: sourceID)
        precondition(io.selectedSourceID == sourceID)
        var received: [(Int, Int, Double)] = []
        io.onMIDI = { note, velocity, time in
            precondition(Thread.isMainThread)
            received.append((note, velocity, time))
        }
        let allocationSize = 4096
        let raw = UnsafeMutableRawPointer.allocate(byteCount: allocationSize, alignment: MemoryLayout<MIDIPacketList>.alignment)
        defer { raw.deallocate() }
        let list = raw.assumingMemoryBound(to: MIDIPacketList.self)
        var packet = MIDIPacketListInit(list)
        let nativeTime = mach_absolute_time()
        let nativeTime2 = nativeTime + 240_000
        func add(_ bytes: [UInt8], _ time: MIDITimeStamp) {
            packet = bytes.withUnsafeBufferPointer {
                MIDIPacketListAdd(list, allocationSize, packet, time, $0.count, $0.baseAddress!)
            }
        }
        // More than 256 bytes exercises variable-length packet storage.
        var notes: [UInt8] = []
        for _ in 0..<100 { notes += [0x99, 42, 80] }
        add(notes, nativeTime)
        add([0x99, 36, 110, 0x99, 38, 0, 0x89, 42, 60], nativeTime2)
        precondition(MIDIReceived(source, list) == noErr)
        let deadline = Date().addingTimeInterval(2)
        while received.count < 101 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(received.count == 101, "Expected 101 note-ons; got \(received.count)")
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let tick = Double(info.numer) / Double(info.denom) / 1_000_000_000
        precondition(abs(received[0].2 - Double(nativeTime) * tick) < 0.000_001)
        precondition(abs(received[100].2 - Double(nativeTime2) * tick) < 0.000_001)
        precondition(received[100].0 == 36 && received[100].1 == 110)
        io.connect(sourceID: nil)
        precondition(io.selectedSourceID == nil)
        print("PASS virtual CoreMIDI: source discovery, connection, 300-byte packet, multiple packets, main callback, original timestamps, disconnect")

        // A device can disappear and return with the same unique ID before the
        // main run loop processes either notification. Its endpoint is new.
        io.connect(sourceID: sourceID)
        precondition(MIDIEndpointDispose(source) == noErr)
        precondition(MIDISourceCreate(client, "Drumx Check Reconnected" as CFString, &source) == noErr)
        precondition(MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, sourceID) == noErr)
        io.refreshSources()
        precondition(io.selectedSourceID == sourceID)
        received.removeAll()
        packet = MIDIPacketListInit(list)
        add([0x99, 51, 95], mach_absolute_time())
        precondition(MIDIReceived(source, list) == noErr)
        let reconnectDeadline = Date().addingTimeInterval(2)
        while received.isEmpty && Date() < reconnectDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(received.count == 1 && received[0].0 == 51)
        io.connect(sourceID: nil)
        print("PASS coalesced MIDI hotplug: stable source ID reconnects to new endpoint")
        precondition(!io.startClick(bpm: 0, firstBeatHostTime: DrumxIO.hostNowSeconds() + 1, beats: 8))
        precondition(!io.startClick(bpm: 90, firstBeatHostTime: DrumxIO.hostNowSeconds() - 1, beats: 8))
        print("PASS invalid audio schedules rejected without starting output")
        let started = io.startClick(bpm: 90, firstBeatHostTime: DrumxIO.hostNowSeconds() + 2, beats: 4)
        if started {
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            io.stopClick() // Stop before any scheduled click is audible.
            precondition(io.sampleRate > 0)
            print("PASS native audio startup and silent preroll: \(Int(io.sampleRate)) Hz, reported output latency \(io.outputLatencySeconds * 1000) ms")
        } else {
            print("AUDIO UNAVAILABLE: \(io.audioStatusDescription)")
        }
        if CommandLine.arguments.count > 1 {
            try checkSampler(URL(fileURLWithPath: CommandLine.arguments[1]), io: io,
                             source: source, sourceID: sourceID)
        } else {
            print("Sampler asset checks skipped: pass BigRusty/manifest.json as the first argument.")
        }
    }

    static func checkSampler(_ manifestURL: URL, io: DrumxIO,
                             source: MIDIEndpointRef, sourceID: Int32) throws {
        let bank = try DrumxSampleBank.load(manifestURL: manifestURL, sampleRate: 44_100)
        precondition(bank.buffers.count == 24 && bank.selector.layers.count == 12)
        for buffer in bank.buffers {
            precondition(buffer.frameLength > 0 && buffer.format.channelCount == 2)
            let samples = buffer.floatChannelData![0]
            let peak = (0..<Int(buffer.frameLength)).reduce(Float(0)) { max($0, abs(samples[$1])) }
            precondition(peak > 0.0001, "Decoded sample must contain actual audio")
        }
        for layer in bank.selector.layers {
            precondition(layer.sampleIndices.count == 2)
            let first = bank.buffers[layer.sampleIndices[0]]
            let second = bank.buffers[layer.sampleIndices[1]]
            let a = first.floatChannelData![0], b = second.floatChannelData![0]
            let differs = first.frameLength != second.frameLength ||
                (0..<Int(min(first.frameLength, second.frameLength))).contains { abs(a[$0] - b[$0]) > 0.0001 }
            precondition(differs, "Alternates must contain different recordings")
        }
        var selector = bank.selector
        for pad in 0..<3 {
            for velocity in [1, 31, 32, 63, 64, 95, 96, 127] {
                let first = selector.select(pad: pad, velocity: velocity)!
                let second = selector.select(pad: pad, velocity: velocity)!
                let third = selector.select(pad: pad, velocity: velocity)!
                precondition(first != second && first == third)
                let entry = selector.entries[first]
                precondition(entry.pad == pad && (entry.velocityMin...entry.velocityMax).contains(velocity))
            }
        }
        precondition(selector.select(pad: 0, velocity: 0) == nil)
        precondition(selector.select(pad: 0, velocity: 128) == nil)
        precondition(selector.select(pad: 99, velocity: 100) == nil)
        print("PASS sample bank: 24 non-silent PCM recordings, 12 layers, distinct alternates, all velocity boundaries, deterministic round robin")

        let sampler = DrumxSampler()
        try sampler.load(manifestURL: manifestURL)
        sampler.setVolume(0) // Scheduling tests remain inaudible.
        sampler.setMapping([[42], [38], [36]])
        sampler.setMIDIGeneration(7)
        sampler.playPad(pad: 0, velocity: 100)
        precondition(sampler.diagnostics().scheduledHits == 0)
        sampler.setEnabled(true)
        precondition(sampler.diagnostics().monitoring, "Sample engine must start")
        let chordStart = DrumxIO.hostNowSeconds()
        for pad in 0..<3 { sampler.playPad(pad: pad, velocity: 100) }
        let chord = sampler.diagnostics()
        let chordMilliseconds = (DrumxIO.hostNowSeconds() - chordStart) * 1000
        print("Sampler warm 3-hit control-queue scheduling: \(chordMilliseconds) ms (software scheduling only)")
        precondition(chord.scheduledHits == 3 && chordMilliseconds < 10,
                     "Three simultaneous pads must reach the warmed player pool promptly")
        let base = chord.scheduledHits
        sampler.playPad(pad: 0, velocity: 100)
        sampler.playPad(pad: 0, velocity: 100)
        precondition(sampler.diagnostics().scheduledHits == base + 2)
        sampler.setLearnActive(true)
        sampler.receiveMIDI(note: 38, velocity: 100, generation: 7)
        precondition(sampler.diagnostics().scheduledHits == base + 2)
        sampler.setLearnActive(false)
        sampler.receiveMIDI(note: 38, velocity: 100, generation: 6)
        sampler.receiveMIDI(note: 99, velocity: 100, generation: 7)
        precondition(sampler.diagnostics().scheduledHits == base + 2)
        sampler.receiveMIDI(note: 38, velocity: 100, generation: 7)
        let beforeStale = sampler.diagnostics()
        precondition(beforeStale.scheduledHits == base + 3)
        sampler.receiveMIDI(note: 38, velocity: 100, generation: 7,
                            receivedAt: DrumxIO.hostNowSeconds() - 1)
        let stale = sampler.diagnostics()
        precondition(stale.scheduledHits == base + 3 &&
                     stale.staleHitsDropped == beforeStale.staleHitsDropped + 1)
        for _ in 0..<40 { sampler.playPad(pad: 2, velocity: 110) }
        let busy = sampler.diagnostics()
        precondition(busy.activeVoices <= 32 && busy.voicesStolen > 0,
            "Sampler burst: \(busy.scheduledHits) scheduled, \(busy.staleHitsDropped) stale, \(busy.activeVoices) voices, \(busy.voicesStolen) stolen")
        sampler.setEnabled(false)
        sampler.playPad(pad: 0, velocity: 100)
        let off = sampler.diagnostics()
        precondition(!off.monitoring && off.activeVoices == 0 && off.scheduledHits == busy.scheduledHits)
        print("PASS sampler scheduling: silent when disabled, keyboard/MIDI share pool, learn suppression, generation/mapping guards, stale-hit discard, overlap, 32-voice cap and stealing")

        try io.loadSampler(manifestURL: manifestURL)
        io.setMonitorVolume(0)
        io.setMIDIMapping([[42], [38], [36]])
        io.connect(sourceID: sourceID)
        io.setMonitoring(enabled: true)
        precondition(io.samplerDiagnostics.monitoring)
        var uiDeliveries = 0
        io.onMIDI = { _, _, _ in uiDeliveries += 1 }
        var list = MIDIPacketList()
        withUnsafeMutablePointer(to: &list) { pointer in
            let packet = MIDIPacketListInit(pointer)
            [UInt8(0x99), 38, 110].withUnsafeBufferPointer { bytes in
                _ = MIDIPacketListAdd(pointer, MemoryLayout<MIDIPacketList>.size, packet,
                                      mach_absolute_time(), bytes.count, bytes.baseAddress!)
            }
            precondition(MIDIReceived(source, pointer) == noErr)
        }
        let until = DrumxIO.hostNowSeconds() + 0.5
        // Intentionally do not service the main run loop. Only native MIDI and
        // the sampler's independent control queue may process this strike.
        while io.samplerDiagnostics.scheduledHits == 0 && DrumxIO.hostNowSeconds() < until {
            Thread.sleep(forTimeInterval: 0.001)
        }
        precondition(io.samplerDiagnostics.scheduledHits == 1 && uiDeliveries == 0)
        io.setMonitoring(enabled: false)
        io.connect(sourceID: nil)
        print("PASS native MIDI monitoring while main/UI delivery is stalled")
    }
}
