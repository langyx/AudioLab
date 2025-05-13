//
//  AudioEngineModel.swift
//  AudioLab
//
//  Created by Yannis Lang on 09/05/2025.
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

class AudioEngineModel: ObservableObject {
    // Engine principal
    private var audioEngine = AVAudioEngine()
    
    // Nœuds pour la lecture et l'enregistrement
    private var playerNode = AVAudioPlayerNode()
    private var micNode: AVAudioInputNode?
    
    // Nœuds d'effets
    private var pitchNode = AVAudioUnitTimePitch()
    private var reverbNode = AVAudioUnitReverb()
    private var eqNode = AVAudioUnitEQ(numberOfBands: 3)
    
    // Fichier audio et format
    private var audioFile: AVAudioFile?
    private var audioFormat: AVAudioFormat?
    private var recordingFile: AVAudioFile?
    
    // État de lecture et d'enregistrement
    @Published var isPlaying = false
    @Published var isRecording = false
    
    // Paramètres des effets
    @Published var pitch: Float = 0.0 {
        didSet {
            pitchNode.pitch = pitch
        }
    }
    
    @Published var reverb: Float = 0.0 {
        didSet {
            reverbNode.wetDryMix = reverb
        }
    }
    
    @Published var eqLow: Float = 0.0 {
        didSet {
            eqNode.bands[0].gain = eqLow
        }
    }
    
    @Published var eqMid: Float = 0.0 {
        didSet {
            eqNode.bands[1].gain = eqMid
        }
    }
    
    @Published var eqHigh: Float = 0.0 {
        didSet {
            eqNode.bands[2].gain = eqHigh
        }
    }
    
    @Published var micVolume: Float = 1.0 {
        didSet {
            audioEngine.inputNode.volume = micVolume
        }
    }
    
    @Published var playerVolume: Float = 1.0 {
        didSet {
            playerNode.volume = playerVolume
        }
    }
    
    init() {
        setupAudioSession()
        setupAudioEngine()
        loadAudioFile()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Erreur lors de la configuration de la session audio: \(error.localizedDescription)")
        }
    }
    
    private func setupAudioEngine() {
        // Configuration des nœuds d'effets
        pitchNode.pitch = 0.0
        reverbNode.wetDryMix = 0.0
        
        // Configuration de l'égaliseur
        eqNode.bands[0].frequency = 80.0
        eqNode.bands[0].bandwidth = 1.0
        eqNode.bands[0].gain = 0.0
        
        eqNode.bands[1].frequency = 1000.0
        eqNode.bands[1].bandwidth = 1.0
        eqNode.bands[1].gain = 0.0
        
        eqNode.bands[2].frequency = 10000.0
        eqNode.bands[2].bandwidth = 1.0
        eqNode.bands[2].gain = 0.0
        
        // Attacher les nœuds à l'engine
        audioEngine.attach(playerNode)
        audioEngine.attach(pitchNode)
        audioEngine.attach(reverbNode)
        audioEngine.attach(eqNode)
        
        // Connexion des nœuds
        audioEngine.connect(playerNode, to: pitchNode, format: nil)
        audioEngine.connect(pitchNode, to: eqNode, format: nil)
        audioEngine.connect(eqNode, to: reverbNode, format: nil)
        audioEngine.connect(reverbNode, to: audioEngine.mainMixerNode, format: nil)
        
        // Connexion du microphone
        micNode = audioEngine.inputNode
        if let micNode = micNode {
            let inputFormat = micNode.outputFormat(forBus: 0)
            audioEngine.connect(micNode, to: audioEngine.mainMixerNode, format: inputFormat)
        }
        
        // Démarrer l'engine
        do {
            try audioEngine.start()
        } catch {
            print("Erreur lors du démarrage de l'engine audio: \(error.localizedDescription)")
        }
    }
    
    private func loadAudioFile() {
        guard let url = Bundle.main.url(forResource: "sample", withExtension: "mp3") else {
            print("Fichier audio non trouvé dans le bundle")
            return
        }
        
        do {
            audioFile = try AVAudioFile(forReading: url)
            audioFormat = audioFile?.processingFormat
        } catch {
            print("Erreur lors du chargement du fichier audio: \(error.localizedDescription)")
        }
    }
    
    func playAudio() async {
        guard let audioFile else { return }
        
        if isPlaying {
            playerNode.stop()
            isPlaying = false
        } else {
            await playerNode.scheduleFile(audioFile, at: nil)
//            playerNode.scheduleFile(audioFile, at: nil) {
//                DispatchQueue.main.async {
//                    self.isPlaying = false
//                }
//            }
            playerNode.play()
            isPlaying = true
        }
    }
    
    func startRecording() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingURL = documentsPath.appendingPathComponent("recording.caf")
        
        try? FileManager.default.removeItem(at: recordingURL)
        
        guard let format = micNode?.outputFormat(forBus: 0) else { return }
        
        do {
            recordingFile = try AVAudioFile(forWriting: recordingURL, settings: format.settings)
            
            micNode?.installTap(onBus: 0, bufferSize: 1024, format: format) { (buffer, time) in
                try? self.recordingFile?.write(from: buffer)
            }
            
            isRecording = true
        } catch {
            print("Erreur lors de l'enregistrement: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        micNode?.removeTap(onBus: 0)
        isRecording = false
    }
    
    func export() async throws -> URL? {
        guard let recordingFile = recordingFile else {
            return nil
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportURL = documentsPath.appendingPathComponent("export.m4a")
        
        try? FileManager.default.removeItem(at: exportURL)
        
        let asset = AVURLAsset(url: recordingFile.url) //AVAsset(url: recordingFile.url)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        
        try await exportSession.export(to: exportURL, as: .m4a)
        
        return exportURL
    }
}
