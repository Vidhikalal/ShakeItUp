import SwiftUI

struct ContentView: View {
    @StateObject private var detector = BeatDetector()
    
    // Animation state for the ripples
    @State private var rippleScale: CGFloat = 0.5
    @State private var rippleOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            // 1. DYNAMIC BACKGROUND
            // Flashes bright when a beat hits, otherwise stays dark/moody
            LinearGradient(
                colors: detector.isBeat ?
                    [Color(red: 0.1, green: 0.1, blue: 0.1), Color.yellow.opacity(0.8)] :
                    [Color.black, Color(red: 0.1, green: 0.1, blue: 0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.05), value: detector.isBeat)
            
            VStack {
                Spacer()
                
                // 2. MAIN BEAT VISUALIZER (The "Speaker")
                ZStack {
                    // Outer Ripples (Visual Echo)
                    ForEach(0..<2) { i in
                        Circle()
                            .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                            .frame(width: 200, height: 200)
                            .scaleEffect(detector.isBeat ? 2.0 : 0.8)
                            .opacity(detector.isBeat ? 0.0 : 0.5)
                            .animation(
                                .easeOut(duration: 0.6).delay(Double(i) * 0.1),
                                value: detector.isBeat
                            )
                    }
                    
                    // Core Pulse Circle
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.yellow, Color.orange],
                                center: .center,
                                startRadius: 10,
                                endRadius: 100
                            )
                        )
                        .frame(width: 180, height: 180)
                        .scaleEffect(detector.isBeat ? 1.15 : 1.0)
                        .shadow(color: .orange, radius: detector.isBeat ? 20 : 0)
                        .overlay {
                            VStack(spacing: 5) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 40))
                                    .symbolEffect(.bounce, value: detector.isBeat)
                                
                                Text(detector.isBeat ? "HIT" : "LISTENING")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .fontDesign(.monospaced)
                            }
                            .foregroundStyle(.black.opacity(0.8))
                        }
                        .animation(.spring(response: 0.1, dampingFraction: 0.3), value: detector.isBeat)
                }
                .padding(.bottom, 50)
                
                Spacer()
                
                // 3. CONTROL PANEL (Glassmorphism Style)
                VStack(spacing: 20) {
                    // Volume Meter
                    HStack {
                        Text("INPUT LEVEL")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white.opacity(0.6))
                        
                        Spacer()
                        
                        // Simulated LED Bar
                        HStack(spacing: 2) {
                            ForEach(0..<15, id: \.self) { index in
                                Capsule()
                                    .fill(
                                        index < Int(detector.volume * 80) ?
                                        (index > 10 ? Color.red : Color.green) :
                                        Color.white.opacity(0.1)
                                    )
                                    .frame(width: 4, height: 12)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider().background(Color.white.opacity(0.2))
                    
                    // Sensitivity Slider
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "ear.badge.checkmark")
                                .foregroundStyle(.orange)
                            Text("SENSITIVITY")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(String(format: "%.1f", detector.sensitivity))")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                        
                        Slider(value: $detector.sensitivity, in: 1.1...2.5)
                            .tint(.orange)
                        
                        HStack {
                            Text("Everything")
                            Spacer()
                            Text("Loud Only")
                        }
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal)
                    
                    // Test Button
                    Button(action: {
                        detector.triggerBeatHaptic(intensity: 1.0)
                    }) {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("FORCE PULSE")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                        .shadow(color: .orange.opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal)
                    .padding(.top, 5)
                }
                .padding(.vertical, 25)
                .background(.ultraThinMaterial) // Glass effect
                .cornerRadius(30)
                .overlay(
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding()
            }
        }
        .onAppear {
            detector.start()
        }
        .preferredColorScheme(.dark) // Force dark mode for neon look
    }
}

#Preview {
    ContentView()
}
