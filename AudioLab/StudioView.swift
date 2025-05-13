//
//  ContentView.swift
//  AudioLab
//
//  Created by Yannis Lang on 09/05/2025.
//
import SwiftUI

struct StudioView: View {
    @StateObject private var audioModel = AudioEngineModel()
    @State private var exportMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Section de lecture
                    playSection
                    
                    // Section d'enregistrement
                    recordSection
                    
                    // Section des effets
                    fxSection
                }
                .padding(.vertical)
            }
            .navigationTitle("Audio Studio")
        }
    }
    
    var playSection: some View {
        GroupBox(label: Text("Lecture")) {
            Button(action: {
                Task {
                    await audioModel.playAudio()
                }
            }) {
                HStack {
                    Image(systemName: audioModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                    Text(audioModel.isPlaying ? "Pause" : "Lecture")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.2))
                .cornerRadius(10)
            }
            
            VStack(alignment: .leading) {
                Text("Volume de lecture: \(Int(audioModel.playerVolume * 100))%")
                Slider(value: $audioModel.playerVolume, in: 0...1)
            }
            .padding(.top)
        }
        .padding()
    }
    
    var recordSection: some View {
        GroupBox(label: Text("Enregistrement")) {
            Button(action: {
                if audioModel.isRecording {
                    audioModel.stopRecording()
                } else {
                    audioModel.startRecording()
                }
            }) {
                Label(audioModel.isRecording ? "Arrêter" : "Enregistrer", systemImage: audioModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .padding()
                .cornerRadius(10)
            }
            
            VStack(alignment: .leading) {
                Text("Volume du micro: \(Int(audioModel.micVolume * 100))%")
                Slider(value: $audioModel.micVolume, in: 0...1)
            }
            .padding(.top)
            
            Button(action: {
                Task {
                    do {
                        if let url = try await audioModel.export() {
                            print("success \(url.absoluteString)")
                        }else{
                            print("failed")
                        }
                    }catch{
                        print(error)
                    }
                }
            }) {
                Text("Exporter en M4A")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(10)
            }
            .padding(.top)
            
            if !exportMessage.isEmpty {
                Text(exportMessage)
                    .font(.caption)
                    .padding(.top, 5)
            }
        }
        .padding()
    }
    
    var fxSection: some View {
        GroupBox(label: Text("Effets audio")) {
            VStack(alignment: .leading, spacing: 15) {
                // Pitch
                VStack(alignment: .leading) {
                    Text("Pitch: \(Int(audioModel.pitch)) cents")
                    Slider(value: $audioModel.pitch, in: -2400...2400, step: 100)
                }
                
                // Reverb
                VStack(alignment: .leading) {
                    Text("Réverbération: \(Int(audioModel.reverb))%")
                    Slider(value: $audioModel.reverb, in: 0...100)
                }
                
                // Égaliseur
                Text("Égaliseur").font(.headline).padding(.top)
                
                VStack(alignment: .leading) {
                    Text("Basses: \(Int(audioModel.eqLow)) dB")
                    Slider(value: $audioModel.eqLow, in: -12...12, step: 1)
                }
                
                VStack(alignment: .leading) {
                    Text("Médiums: \(Int(audioModel.eqMid)) dB")
                    Slider(value: $audioModel.eqMid, in: -12...12, step: 1)
                }
                
                VStack(alignment: .leading) {
                    Text("Aigus: \(Int(audioModel.eqHigh)) dB")
                    Slider(value: $audioModel.eqHigh, in: -12...12, step: 1)
                }
            }
        }
        .padding()
    }
}

#Preview {
    StudioView()
}
