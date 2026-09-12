import Foundation
import CoreMIDI
import AVFoundation
import Darwin
import Synchronization

public struct MIDISourceInfo: Equatable {
    public let id: Int32
    public let name: String
}

/// Native I/O for the Mac timing lab. Call its public methods on the main thread.
/// All public callbacks run on the main thread, but a MIDI event's time is the
/// original CoreMIDI host timestamp, not the time its UI callback executes.
/// Host seconds are monotonic mach_absolute_time seconds, never wall-clock time.
final class DrumxIO {
    var onMIDI: ((Int, Int, Double) -> Void)?
    var onSourcesChanged: (([MIDISourceInfo]) -> Void)?
    var onConnectionChanged: (() -> Void)?
    var onStatusChanged: ((String) -> Void)?
    /// The click has stopped and the current attempt must not continue scoring.
    var onAudioInterrupted: ((String) -> Void)?
    var onSamplerStatusChanged: ((String) -> Void)?
    private(set) var samplerStatusDescription = "Drum samples not loaded"
    var samplerDiagnostics: DrumxSamplerDiagnostics { sampler.diagnostics() }
    var demoDurationSeconds: Double { sampler.demoDurationSeconds }

    private(set) var sources: [MIDISourceInfo] = []
    private(set) var selectedSourceID: Int32?
    private(set) var sampleRate: Double = 0
    private(set) var statusDescription = "MIDI ready. Choose a source."
    /// Number of note-on events whose device supplied zero instead of a timestamp.
    private(set) var zeroTimestampCount = 0
    /// Reported pipeline estimate, not a physical end-to-end latency measurement.
    private(set) var outputLatencySeconds: Double = 0
    private(set) var audioStatusDescription = "Click stopped"

    private var midiClient = MIDIClientRef()
    private var midiPort = MIDIPortRef()
    private var connectedEndpoint = MIDIEndpointRef()
    private var connectionGeneration: UInt64 = 0
    private var engine: AVAudioEngine?
    private var audioConfigurationObserver: NSObjectProtocol?
    private var audioHealthTimer: Timer?
    private let sampler = DrumxSampler()

    private static let secondsPerHostTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    static func hostNowSeconds() -> Double {
        Double(mach_absolute_time()) * secondsPerHostTick
    }

    init() {
        sampler.onStatusChanged = { [weak self] message in
            self?.samplerStatusDescription = message
            self?.onSamplerStatusChanged?(message)
        }
        sampler.onAudioInterrupted = { [weak self] reason in self?.interruptAudio(reason) }
        let result = MIDIClientCreateWithBlock("Drumx Timing Lab" as CFString, &midiClient) {
            [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.refreshSources() }
        }
        if result != noErr {
            updateStatus("CoreMIDI unavailable (\(result)). Keyboard practice remains available.")
        } else {
            refreshSources()
        }
    }

    deinit {
        if let observer = audioConfigurationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        engine?.stop()
        audioHealthTimer?.invalidate()
        if midiPort != 0 { MIDIPortDispose(midiPort) }
        if midiClient != 0 { MIDIClientDispose(midiClient) }
    }

    func refreshSources() {
        guard midiClient != 0 else { return }
        var updated: [MIDISourceInfo] = []
        var selectedEndpointNow = MIDIEndpointRef()
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }
            let identifier = sourceID(endpoint)
            updated.append(MIDISourceInfo(id: identifier, name: sourceName(endpoint)))
            if identifier == selectedSourceID { selectedEndpointNow = endpoint }
        }
        sources = updated
        if let selected = selectedSourceID, !updated.contains(where: { $0.id == selected }) {
            disconnectPort()
            selectedSourceID = nil
            updateStatus("MIDI source disconnected. Choose another source or use the keyboard.")
        } else if let selected = selectedSourceID, selectedEndpointNow != connectedEndpoint {
            // Removal/reappearance notifications can coalesce before the main
            // thread runs. A stable ID can refer to a newly created endpoint.
            connect(sourceID: selected)
        }
        onSourcesChanged?(updated)
    }

    /// Select exactly one MIDI input. nil explicitly disconnects MIDI input.
    /// A fresh parser and port ensure messages from a previous source are discarded.
    func connect(sourceID requestedID: Int32?) {
        defer { onConnectionChanged?() }
        disconnectPort()
        selectedSourceID = nil
        zeroTimestampCount = 0
        guard let requestedID else {
            updateStatus("MIDI disconnected. Keyboard input available.")
            return
        }
        guard midiClient != 0 else {
            updateStatus("CoreMIDI unavailable. Keyboard input available.")
            return
        }
        var endpoint = MIDIEndpointRef()
        for index in 0..<MIDIGetNumberOfSources() {
            let candidate = MIDIGetSource(index)
            if candidate != 0 && sourceID(candidate) == requestedID {
                endpoint = candidate
                break
            }
        }
        guard endpoint != 0 else {
            updateStatus("That MIDI source is no longer available.")
            refreshSources()
            return
        }

        let generation = connectionGeneration
        let tickSeconds = Self.secondsPerHostTick
        let parser = MIDIByteStreamParser()
        let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
        let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \.data)!
        let inputSampler = sampler
        let createStatus = MIDIInputPortCreateWithBlock(midiClient, "Drumx Input" as CFString, &midiPort) {
            [weak self] packetList, _ in
            let arrival = Self.hostNowSeconds()
            var packet = UnsafeRawPointer(packetList)
                .advanced(by: packetOffset).assumingMemoryBound(to: MIDIPacket.self)
            for _ in 0..<packetList.pointee.numPackets {
                let nativeTimestamp = packet.pointee.timeStamp
                let usesArrival = nativeTimestamp == 0
                let hostSeconds = usesArrival ? arrival : Double(nativeTimestamp) * tickSeconds
                // Packet data is variable-length. Walk the original list, never a
                // copied 256-byte tuple, and use CoreMIDI's platform-aware stride.
                let bytes = UnsafeRawPointer(packet).advanced(by: dataOffset)
                    .assumingMemoryBound(to: UInt8.self)
                parser.consume(bytes: bytes, count: Int(packet.pointee.length),
                               hostSeconds: hostSeconds, usesArrival: usesArrival) { note, velocity, time, fallback in
                    inputSampler.receiveMIDI(note: note, velocity: velocity, generation: generation,
                                             receivedAt: arrival)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.connectionGeneration == generation,
                              self.selectedSourceID == requestedID else { return }
                        if fallback { self.zeroTimestampCount += 1 }
                        self.onMIDI?(note, velocity, time)
                    }
                }
                packet = UnsafePointer(MIDIPacketNext(packet))
            }
        }
        guard createStatus == noErr else {
            midiPort = 0
            updateStatus("Could not create MIDI input (\(createStatus)).")
            return
        }
        let connectStatus = MIDIPortConnectSource(midiPort, endpoint, nil)
        guard connectStatus == noErr else {
            disconnectPort()
            updateStatus("Could not connect MIDI source (\(connectStatus)).")
            return
        }
        connectedEndpoint = endpoint
        selectedSourceID = requestedID
        updateStatus("MIDI: \(sourceName(endpoint))")
    }

    /// Schedule a finite quarter-note click. firstBeatHostTime is the desired
    /// presentation time in host seconds. Rendering is advanced by the device's
    /// reported presentation latency plus known downstream processing latency.
    /// This is an estimate: kit scanning, USB, headphones and the player's acoustic
    /// path still require empirical calibration. No low-latency claim is implied.
    @discardableResult
    func startClick(bpm: Double, firstBeatHostTime: Double, beats: Int) -> Bool {
        stopClick()
        guard bpm.isFinite, bpm >= 20, bpm <= 400, beats > 0, beats <= 4096,
              firstBeatHostTime.isFinite, firstBeatHostTime > Self.hostNowSeconds() else {
            audioStatusDescription = "Click needs a valid tempo and a future start time."
            updateStatus(audioStatusDescription)
            return false
        }

        let newEngine = AVAudioEngine()
        let output = newEngine.outputNode
        let hardwareFormat = output.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: hardwareFormat.sampleRate,
                                         channels: min(hardwareFormat.channelCount, 2)) else {
            audioStatusDescription = "No usable audio output device."
            updateStatus(audioStatusDescription)
            return false
        }
        sampleRate = format.sampleRate
        // Timing/configuration captures are immutable. The sole shared render
        // state is an atomic health flag. No allocation, locks, logging,
        // dispatch or UI access occurs on the audio render thread.
        let rate = format.sampleRate
        let secondsPerFrame = 1.0 / rate
        let tickSeconds = Self.secondsPerHostTick
        let interval = 60.0 / bpm
        let duration = Double(beats) * interval
        let latency = max(0, output.presentationLatency + output.latency + newEngine.mainMixerNode.latency)
        outputLatencySeconds = latency
        let renderHealth = AudioRenderHealth()
        let source = AVAudioSourceNode(format: format) { isSilence, timestamp, frameCount, outputData in
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            let hasHostTime = timestamp.pointee.mFlags.contains(.hostTimeValid)
            // Without a valid native clock, output silence rather than inventing
            // an audio/scoring alignment. A main-thread watchdog ends the take
            // if that condition persists; the render callback never dispatches.
            renderHealth.hasValidTimestamp.store(hasHostTime, ordering: .relaxed)
            let firstFrame = Double(timestamp.pointee.mHostTime) * tickSeconds + latency
            var sounded = false
            for frame in 0..<Int(frameCount) {
                var value: Float = 0
                if hasHostTime {
                    let elapsed = firstFrame + Double(frame) * secondsPerFrame - firstBeatHostTime
                    if elapsed >= 0 && elapsed < duration {
                        let beatIndex = Int(elapsed / interval)
                        let phaseSeconds = elapsed - Double(beatIndex) * interval
                        if phaseSeconds < 0.028 {
                            let accented = beatIndex % 4 == 0
                            let frequency = accented ? 1760.0 : 1174.66
                            let attack = min(1.0, phaseSeconds / 0.0008)
                            let decay = exp(-phaseSeconds * 190.0)
                            value = Float(sin(phaseSeconds * frequency * 2.0 * Double.pi)
                                          * attack * decay * (accented ? 0.28 : 0.20))
                            sounded = sounded || value != 0
                        }
                    }
                }
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    // The source format is Float32, non-interleaved.
                    data.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            isSilence.pointee = ObjCBool(!sounded)
            return noErr
        }
        newEngine.attach(source)
        newEngine.connect(source, to: newEngine.mainMixerNode, format: format)
        newEngine.prepare()
        do {
            try newEngine.start()
        } catch {
            newEngine.stop()
            audioStatusDescription = "Audio could not start: \(error.localizedDescription)"
            updateStatus(audioStatusDescription)
            return false
        }
        guard firstBeatHostTime - Self.hostNowSeconds() > latency else {
            newEngine.stop()
            audioStatusDescription = "Audio started too late for count-in. Try again."
            updateStatus(audioStatusDescription)
            return false
        }
        engine = newEngine
        audioConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: newEngine, queue: .main
        ) { [weak self, weak newEngine] _ in
            guard let self, let newEngine, self.engine === newEngine else { return }
            self.interruptAudio("Audio device changed. Restart the attempt.")
        }
        var missingTimestampChecks = 0
        audioHealthTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self, weak newEngine] _ in
            guard let self, let newEngine, self.engine === newEngine else { return }
            if renderHealth.hasValidTimestamp.load(ordering: .relaxed) {
                missingTimestampChecks = 0
            } else {
                missingTimestampChecks += 1
                if missingTimestampChecks >= 2 {
                    self.interruptAudio("Audio clock unavailable. Restart the attempt.")
                }
            }
        }
        audioStatusDescription = "Click ready · \(Int(rate)) Hz"
        updateStatus(audioStatusDescription)
        return true
    }

    func stopClick() {
        let wasRunning = engine != nil
        audioHealthTimer?.invalidate()
        audioHealthTimer = nil
        if let observer = audioConfigurationObserver {
            NotificationCenter.default.removeObserver(observer)
            audioConfigurationObserver = nil
        }
        engine?.stop()
        engine = nil
        audioStatusDescription = "Click stopped"
        if wasRunning { updateStatus(audioStatusDescription) }
    }

    private func interruptAudio(_ reason: String) {
        stopClick()
        stopDemo()
        audioStatusDescription = reason
        updateStatus(reason)
        onAudioInterrupted?(reason)
    }

    private func disconnectPort() {
        connectionGeneration &+= 1
        sampler.setMIDIGeneration(connectionGeneration)
        if midiPort != 0 {
            if connectedEndpoint != 0 { MIDIPortDisconnectSource(midiPort, connectedEndpoint) }
            MIDIPortDispose(midiPort)
            midiPort = 0
        }
        connectedEndpoint = 0
    }

    private func sourceID(_ endpoint: MIDIEndpointRef) -> Int32 {
        var identifier: Int32 = 0
        if MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &identifier) == noErr {
            return identifier
        }
        return Int32(bitPattern: endpoint)
    }

    private func sourceName(_ endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr,
           let name { return name.takeRetainedValue() as String }
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name) == noErr,
           let name { return name.takeRetainedValue() as String }
        return "MIDI source \(sourceID(endpoint))"
    }

    private func updateStatus(_ status: String) {
        statusDescription = status
        onStatusChanged?(status)
    }

    func loadSampler(manifestURL: URL) throws {
        try sampler.load(manifestURL: manifestURL)
        samplerStatusDescription = "Drum samples loaded"
    }

    func setMonitoring(enabled: Bool) { sampler.setEnabled(enabled) }
    func setMonitorVolume(_ volume: Float) { sampler.setVolume(volume) }
    func setMIDIMapping(_ notesByPad: [[Int]]) { sampler.setMapping(notesByPad) }
    func setMIDILearnActive(_ active: Bool) { sampler.setLearnActive(active) }
    /// Use for keyboard input. Native MIDI is already monitored before UI dispatch.
    func playPad(pad: Int, velocity: Int) { sampler.playPad(pad: pad, velocity: velocity) }

    @discardableResult
    func startDemo(bpm: Double, firstBeatHostTime: Double, bars: Int) -> Bool {
        let started = sampler.startDemo(bpm: bpm, firstBeatHostTime: firstBeatHostTime, bars: bars)
        if !started { updateStatus(sampler.demoStatusDescription) }
        return started
    }

    func stopDemo() { sampler.stopDemo() }

    @discardableResult
    func startDemo(bpm: Double, firstBeatHostTime: Double, durationBeats: Double,
                   hits: [DrumxDemoHit]) -> Bool {
        let started = sampler.startDemo(bpm: bpm, firstBeatHostTime: firstBeatHostTime,
                                        durationBeats: durationBeats, hits: hits)
        if !started { updateStatus(sampler.demoStatusDescription) }
        return started
    }
}

/// One instance belongs exclusively to one CoreMIDI receive port. Streaming
/// state supports running status, packet boundaries, system common and realtime
/// messages. Only positive-velocity note-ons become drum strikes.
// Internal visibility lets the native test executable verify the stream parser
// without creating a MIDI endpoint for malformed or deliberately split messages.
final class MIDIByteStreamParser {
    private var status: UInt8 = 0
    private var dataCount = 0
    private var firstData: UInt8 = 0
    private var expectedData = 0
    private var inSysEx = false
    private var waitingAfterStatus = false
    private var messageTime: Double = 0
    private var messageUsesArrival = false

    func consume(bytes: UnsafePointer<UInt8>, count: Int, hostSeconds: Double,
                 usesArrival: Bool, emit: (Int, Int, Double, Bool) -> Void) {
        for index in 0..<count {
            let byte = bytes[index]
            if byte >= 0xF8 { continue } // Realtime may appear inside any message.
            if byte & 0x80 != 0 {
                dataCount = 0
                waitingAfterStatus = true
                messageTime = hostSeconds
                messageUsesArrival = usesArrival
                if byte < 0xF0 {
                    inSysEx = false
                    status = byte
                    expectedData = (byte & 0xF0 == 0xC0 || byte & 0xF0 == 0xD0) ? 1 : 2
                } else {
                    status = byte
                    inSysEx = byte == 0xF0
                    expectedData = byte == 0xF2 ? 2 : ((byte == 0xF1 || byte == 0xF3) ? 1 : 0)
                    if expectedData == 0 { status = 0 }
                }
                continue
            }
            guard !inSysEx, status != 0, expectedData > 0 else { continue }
            if dataCount == 0 {
                firstData = byte
                if !waitingAfterStatus {
                    messageTime = hostSeconds
                    messageUsesArrival = usesArrival
                }
            }
            dataCount += 1
            if dataCount == expectedData {
                if status & 0xF0 == 0x90, expectedData == 2, byte > 0 {
                    emit(Int(firstData), Int(byte), messageTime, messageUsesArrival)
                }
                dataCount = 0
                waitingAfterStatus = false
                if status >= 0xF0 { status = 0; expectedData = 0 }
            }
        }
    }
}

private final class AudioRenderHealth {
    let hasValidTimestamp = Atomic<Bool>(true)
}
