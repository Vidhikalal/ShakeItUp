import Foundation
import AVFoundation
import CoreHaptics
import Combine
import AudioToolbox

class BeatDetector: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var hapticEngine: CHHapticEngine?
    
    @Published var isBeat: Bool = false
    @Published var volume: Float = 0.0
    @Published var sensitivity: Float = 1.3
    
    private var volumeHistory: [Float] = []
    private let historyLimit = 10
    
    init() {
        prepareHaptics()
    }
    
    func start() {
        setupAudio()
    }
    
    private func setupAudio() {
        let session = AVAudioSession.sharedInstance()
        do {
            // FIX 1: FORCE HAPTICS ON. We use .videoRecording mode to trick iOS into keeping the speaker and haptics active.
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth, .allowAirPlay])
            
            // FIX 2: Explicitly allow haptics during recording (Available iOS 13+)
            if #available(iOS 13.0, *) {
                try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            }
            
            try session.setActive(true)
            
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.analyzeBuffer(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            print("✅ Audio Engine Started")
        } catch {
            print("❌ Audio Engine Error: \(error)")
        }
    }
    
    private func analyzeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let ptr = UnsafeBufferPointer(start: channelData, count: frameCount)
        
        // Calculate volume (RMS)
        let sum = ptr.reduce(0) { $0 + ($1 * $1) }
        let rms = sqrt(sum / Float(frameCount))
        
        DispatchQueue.main.async {
            self.volume = rms
            let avgVolume = self.volumeHistory.reduce(0, +) / Float(max(1, self.volumeHistory.count))
            
            // FIX 3: INCREASED SENSITIVITY
            // Lowered the minimum volume floor to 0.005 so it catches quiet beats
            if rms > (avgVolume * self.sensitivity) && rms > 0.005 {
                if !self.isBeat {
                    // Trigger with a multiplier to ensure even weak beats feel strong
                    self.triggerBeatHaptic(intensity: rms * 5.0)
                    self.isBeat = true
                    
                    // Reset faster (0.05s) to catch fast rhythms
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.isBeat = false }
                }
            }
            
            self.volumeHistory.append(rms)
            if self.volumeHistory.count > self.historyLimit { self.volumeHistory.removeFirst() }
        }
    }
    
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            // FIX 4: Auto-Restart engine if it stops
            hapticEngine?.resetHandler = { [weak self] in
                try? self?.hapticEngine?.start()
            }
            try hapticEngine?.start()
        } catch {
            print("❌ Haptic Engine Failed: \(error)")
        }
    }
    
    func triggerBeatHaptic(intensity: Float) {
        // FIX 5: NUCLEAR OPTION (Continuous Buzz + Strong Alert ID)
        
        // Use ID 1352 (System Alert) which ignores the Silent Switch on most phones
        AudioServicesPlaySystemSound(1352)
        
        guard let engine = hapticEngine else { return }
        try? engine.start()
        
        // Boost intensity to maximum
        let strength = min(max(intensity * 20, 0.8), 1.0)
        
        // Use a CONTINUOUS event (Buzz) instead of Transient (Tap)
        // This is much easier to feel
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: strength),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
        ], relativeTime: 0, duration: 0.15) // Buzz for 0.15 seconds
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("❌ Haptic Pattern Error: \(error)")
        }
    }
}
