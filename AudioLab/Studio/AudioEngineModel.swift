
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

/// `AudioEngineModel` gère le traitement audio en temps réel, incluant la lecture,
/// l'enregistrement et l'application d'effets audio.
///
/// Cette classe utilise AVAudioEngine pour créer un graphe de traitement audio
/// permettant la lecture de fichiers, l'enregistrement depuis le microphone,
/// et l'application d'effets comme le pitch, la réverbération et l'égalisation.
@Observable
class AudioEngineModel: ObservableObject {
    // MARK: - Propriétés privées
    
    /// Moteur audio principal qui gère le graphe de traitement audio
    private var audioEngine = AVAudioEngine()
    
    /// Nœud responsable de la lecture des fichiers audio
    private var playerNode = AVAudioPlayerNode()
    
    /// Nœud d'entrée pour capturer l'audio du microphone
    private var micNode: AVAudioInputNode?
    
    /// Mixeur dédié au signal du microphone pour contrôler son volume
    private var micMixerNode = AVAudioMixerNode()
    
    /// Nœud d'effet pour modifier la hauteur (pitch) du son
    private var pitchNode = AVAudioUnitTimePitch()
    
    /// Nœud d'effet pour ajouter de la réverbération
    private var reverbNode = AVAudioUnitReverb()
    
    /// Égaliseur à 3 bandes pour ajuster les fréquences basses, moyennes et hautes
    private var eqNode = AVAudioUnitEQ(numberOfBands: 3)
    
    /// Fichier audio source à lire
    private var audioFile: AVAudioFile?
    
    /// Format audio utilisé pour le traitement
    private var audioFormat: AVAudioFormat?
    
    /// Fichier de destination pour l'enregistrement
    private var recordingFile: AVAudioFile?
    
    // MARK: - Propriétés publiques
    
    /// Indique si la lecture audio est en cours
    var isPlaying = false
    
    /// Indique si l'enregistrement est en cours
    var isRecording = false
    
    /// Amplitude actuelle du signal audio (utilisée pour les visualisations)
    var amplitude: Float = 0
    
    /// Contrôle la hauteur du son (en centièmes de demi-tons)
    /// Une valeur positive augmente la hauteur, une valeur négative la diminue
    var pitch: Float = 0.0 {
        didSet {
            pitchNode.pitch = pitch
        }
    }
    
    /// Contrôle l'intensité de la réverbération (0-100)
    var reverb: Float = 0.0 {
        didSet {
            reverbNode.wetDryMix = reverb
        }
    }
    
    /// Gain pour les basses fréquences de l'égaliseur (en dB)
    var eqLow: Float = 0.0 {
        didSet {
            eqNode.bands[0].gain = eqLow
        }
    }
    
    /// Gain pour les fréquences moyennes de l'égaliseur (en dB)
    var eqMid: Float = 0.0 {
        didSet {
            eqNode.bands[1].gain = eqMid
        }
    }
    
    /// Gain pour les hautes fréquences de l'égaliseur (en dB)
    var eqHigh: Float = 0.0 {
        didSet {
            eqNode.bands[2].gain = eqHigh
        }
    }
    
    /// Volume du microphone (0-1)
    var micVolume: Float = 0 {
        didSet {
            micMixerNode.volume = micVolume
        }
    }
    
    /// Volume du lecteur audio (0-1)
    var playerVolume: Float = 1.0 {
        didSet {
            playerNode.volume = playerVolume
        }
    }
    
    // MARK: - Initialisation
    
    /// Initialise le modèle audio en configurant la session audio,
    /// en préparant le graphe de traitement et en chargeant le fichier audio par défaut
    init() {
        setupAudioSession()
        setupAudioEngine()
        loadAudioFile()
    }
    
    // MARK: - Configuration
    
    /// Configure la session audio pour permettre la lecture et l'enregistrement simultanés
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Erreur lors de la configuration de la session audio: \(error.localizedDescription)")
        }
    }
    
    /// Configure le graphe de traitement audio avec tous les nœuds et leurs connexions
    private func setupAudioEngine() {
        // Configuration des nœuds d'effets
        pitchNode.pitch = 0.0
        reverbNode.wetDryMix = 0.0
        
        // Configuration de l'égaliseur à 3 bandes
        eqNode.bands[0].frequency = 80.0     // Fréquence basse (80 Hz)
        eqNode.bands[0].bandwidth = 1.0      // Largeur de bande en octaves
        eqNode.bands[0].gain = 0.0           // Gain initial à 0 dB
        
        eqNode.bands[1].frequency = 1000.0   // Fréquence moyenne (1 kHz)
        eqNode.bands[1].bandwidth = 1.0
        eqNode.bands[1].gain = 0.0
        
        eqNode.bands[2].frequency = 10000.0  // Fréquence haute (10 kHz)
        eqNode.bands[2].bandwidth = 1.0
        eqNode.bands[2].gain = 0.0
        
        // Configuration des types de filtres pour chaque bande
        eqNode.bands[0].filterType = .lowShelf    // Filtre en plateau pour les basses
        eqNode.bands[1].filterType = .parametric  // Filtre paramétrique pour les médiums
        eqNode.bands[2].filterType = .highShelf   // Filtre en plateau pour les aigus

        // Activer toutes les bandes
        for band in eqNode.bands {
            band.bypass = false
        }
        
        // Attacher tous les nœuds au moteur audio
        audioEngine.attach(playerNode)
        audioEngine.attach(pitchNode)
        audioEngine.attach(reverbNode)
        audioEngine.attach(eqNode)
        audioEngine.attach(micMixerNode)
        
        // Créer la chaîne de traitement pour le signal de lecture
        audioEngine.connect(playerNode, to: pitchNode, format: nil)
        audioEngine.connect(pitchNode, to: eqNode, format: nil)
        audioEngine.connect(eqNode, to: reverbNode, format: nil)
        audioEngine.connect(reverbNode, to: audioEngine.mainMixerNode, format: nil)
        
        // Configuration et connexion du microphone
        micNode = audioEngine.inputNode
        if let micNode = micNode {
            let inputFormat = micNode.outputFormat(forBus: 0)
            // Connecter le micro à son mixer dédié pour contrôler son volume
            audioEngine.connect(micNode, to: micMixerNode, format: inputFormat)
            // Puis connecter le mixer au mixeur principal
            audioEngine.connect(micMixerNode, to: audioEngine.mainMixerNode, format: inputFormat)
        }
        micMixerNode.volume = micVolume
        
        // Démarrer le moteur audio
        do {
            try audioEngine.start()
        } catch {
            print("Erreur lors du démarrage de l'engine audio: \(error.localizedDescription)")
        }
    }
    
    /// Charge le fichier audio par défaut depuis le bundle de l'application
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
    
    // MARK: - Contrôles de lecture et d'enregistrement
    
    /// Démarre ou arrête la lecture du fichier audio
    func playAudio() {
        guard let audioFile else { return }
        
        if isPlaying {
            playerNode.stop()
            isPlaying = false
        } else {
            playerNode.scheduleFile(audioFile, at: nil) {
                self.isPlaying = false
            }
            playerNode.play()
            isPlaying = true
        }
    }
    
    /// Démarre l'enregistrement du signal audio traité
    func startRecording() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        print(documentsPath.absoluteString)
        let recordingURL = documentsPath.appendingPathComponent("recording.caf")
        
        // Supprimer tout enregistrement précédent
        try? FileManager.default.removeItem(at: recordingURL)
        
        // Utiliser le format de sortie du mixeur principal
        let format = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        do {
            recordingFile = try AVAudioFile(forWriting: recordingURL, settings: format.settings)
            
            // Installer un tap sur le mixeur principal pour capturer l'audio
            audioEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [self] (buffer, time) in
                try? self.recordingFile?.write(from: buffer)
                amplitude = calculateRMS(buffer: buffer)
            }
            isRecording = true
        } catch {
            print("Erreur lors de l'enregistrement: \(error.localizedDescription)")
        }
    }
    
    /// Arrête l'enregistrement en cours
    func stopRecording() {
        audioEngine.mainMixerNode.removeTap(onBus: 0)
        amplitude = 0
        isRecording = false
    }
    
    /// Exporte l'enregistrement au format M4A
    /// - Returns: L'URL du fichier exporté, ou nil en cas d'échec
    func export() async throws -> URL? {
        guard let recordingFile = recordingFile else {
            return nil
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportURL = documentsPath.appendingPathComponent("export.m4a")
        
        // Supprimer tout export précédent
        try? FileManager.default.removeItem(at: exportURL)
        
        // Créer une session d'export pour convertir l'enregistrement au format M4A
        let asset = AVURLAsset(url: recordingFile.url)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        
        // Exporter le fichier de manière asynchrone
        try await exportSession.export(to: exportURL, as: .m4a)
        
        return exportURL
    }
    
    // MARK: - Utilitaires
    
    /// Calcule la valeur RMS (Root Mean Square) d'un buffer audio
    /// pour déterminer l'amplitude du signal
    /// - Parameter buffer: Le buffer audio à analyser
    /// - Returns: Une valeur normalisée entre 0 et 1 représentant l'amplitude
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        // Amplification pour l'affichage
        let amplifiedRMS = min(rms * 5.0, 1.0) // Multiplie par 5 et plafonne à 1.0
        
        return amplifiedRMS
    }
}
////
////  AudioEngineModel.swift
////  AudioLab
////
////  Created by Yannis Lang on 09/05/2025.
////
//

//import Foundation
//import AVFoundation
//import SwiftUI
//import Combine
//
//@Observable
//class AudioEngineModel: ObservableObject {
//    // Engine principal
//    private var audioEngine = AVAudioEngine()
//    
//    // Nœuds pour la lecture et l'enregistrement
//    private var playerNode = AVAudioPlayerNode()
//    private var micNode: AVAudioInputNode?
//    private var micMixerNode = AVAudioMixerNode()
//    
//    // Nœuds d'effets
//    private var pitchNode = AVAudioUnitTimePitch()
//    private var reverbNode = AVAudioUnitReverb()
//    private var eqNode = AVAudioUnitEQ(numberOfBands: 3)
//    
//    // Fichier audio et format
//    private var audioFile: AVAudioFile?
//    private var audioFormat: AVAudioFormat?
//    private var recordingFile: AVAudioFile?
//    
//    // État de lecture et d'enregistrement
//    var isPlaying = false
//    var isRecording = false
//    var amplitude: Float = 0
//    
//    // Paramètres des effets
//    var pitch: Float = 0.0 {
//        didSet {
//            pitchNode.pitch = pitch
//        }
//    }
//    
//    var reverb: Float = 0.0 {
//        didSet {
//            reverbNode.wetDryMix = reverb
//        }
//    }
//    
//    var eqLow: Float = 0.0 {
//        didSet {
//            eqNode.bands[0].gain = eqLow
//        }
//    }
//    
//    var eqMid: Float = 0.0 {
//        didSet {
//            eqNode.bands[1].gain = eqMid
//        }
//    }
//    
//    var eqHigh: Float = 0.0 {
//        didSet {
//            eqNode.bands[2].gain = eqHigh
//        }
//    }
//    
//    var micVolume: Float = 0 {
//        didSet {
//            micMixerNode.volume = micVolume
//        }
//    }
//    
//    var playerVolume: Float = 1.0 {
//        didSet {
//            playerNode.volume = playerVolume
//        }
//    }
//    
//    init() {
//        setupAudioSession()
//        setupAudioEngine()
//        loadAudioFile()
//    }
//    
//    private func setupAudioSession() {
//        do {
//            let session = AVAudioSession.sharedInstance()
//            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
//            try session.setActive(true)
//        } catch {
//            print("Erreur lors de la configuration de la session audio: \(error.localizedDescription)")
//        }
//    }
//    
//    private func setupAudioEngine() {
//        // Configuration des nœuds d'effets
//        pitchNode.pitch = 0.0
//        reverbNode.wetDryMix = 0.0
//        
//        // Configuration de l'égaliseur
//        eqNode.bands[0].frequency = 80.0
//        eqNode.bands[0].bandwidth = 1.0
//        eqNode.bands[0].gain = 0.0
//        
//        eqNode.bands[1].frequency = 1000.0
//        eqNode.bands[1].bandwidth = 1.0
//        eqNode.bands[1].gain = 0.0
//        
//        eqNode.bands[2].frequency = 10000.0
//        eqNode.bands[2].bandwidth = 1.0
//        eqNode.bands[2].gain = 0.0
//        
//        eqNode.bands[0].filterType = .lowShelf
//        eqNode.bands[1].filterType = .parametric
//        eqNode.bands[2].filterType = .highShelf
//
//        for band in eqNode.bands {
//            band.bypass = false
//        }
//        
//        // Attacher les nœuds à l'engine
//        audioEngine.attach(playerNode)
//        audioEngine.attach(pitchNode)
//        audioEngine.attach(reverbNode)
//        audioEngine.attach(eqNode)
//        audioEngine.attach(micMixerNode)
//        
//        // Connexion des nœuds
//        audioEngine.connect(playerNode, to: pitchNode, format: nil)
//        audioEngine.connect(pitchNode, to: eqNode, format: nil)
//        audioEngine.connect(eqNode, to: reverbNode, format: nil)
//        audioEngine.connect(reverbNode, to: audioEngine.mainMixerNode, format: nil)
//        
//        // Connexion du microphone
//        micNode = audioEngine.inputNode
//        if let micNode = micNode {
//            let inputFormat = micNode.outputFormat(forBus: 0)
//            // Connecter le micro à son mixer dédié
//            audioEngine.connect(micNode, to: micMixerNode, format: inputFormat)
//            // Puis le mixer à la suite (par exemple, au mainMixerNode)
//            audioEngine.connect(micMixerNode, to: audioEngine.mainMixerNode, format: inputFormat)
//        }
//        micMixerNode.volume = micVolume
//        
//        // Démarrer l'engine
//        do {
//            try audioEngine.start()
//        } catch {
//            print("Erreur lors du démarrage de l'engine audio: \(error.localizedDescription)")
//        }
//    }
//    
//    private func loadAudioFile() {
//        guard let url = Bundle.main.url(forResource: "sample", withExtension: "mp3") else {
//            print("Fichier audio non trouvé dans le bundle")
//            return
//        }
//        
//        do {
//            audioFile = try AVAudioFile(forReading: url)
//            audioFormat = audioFile?.processingFormat
//        } catch {
//            print("Erreur lors du chargement du fichier audio: \(error.localizedDescription)")
//        }
//    }
//    
//    func playAudio() {
//        guard let audioFile else { return }
//        
//        if isPlaying {
//            playerNode.stop()
//            isPlaying = false
//        } else {
//            playerNode.scheduleFile(audioFile, at: nil) {
//                self.isPlaying = false
//            }
//            playerNode.play()
//            isPlaying = true
//        }
//    }
//    
//    func startRecording() {
//        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//        print(documentsPath.absoluteString)
//        let recordingURL = documentsPath.appendingPathComponent("recording.caf")
//        
//        try? FileManager.default.removeItem(at: recordingURL)
//        
//         let format =  audioEngine.mainMixerNode.outputFormat(forBus: 0)
//        do {
//            recordingFile = try AVAudioFile(forWriting: recordingURL, settings: format.settings)
//            
//            audioEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [self] (buffer, time) in
//                try? self.recordingFile?.write(from: buffer)
//                amplitude = calculateRMS(buffer: buffer)
//            }
//            isRecording = true
//        } catch {
//            print("Erreur lors de l'enregistrement: \(error.localizedDescription)")
//        }
//    }
//    
//    func stopRecording() {
//        audioEngine.mainMixerNode.removeTap(onBus: 0)
//        amplitude = 0
//        isRecording = false
//    }
//    
//    func export() async throws -> URL? {
//        guard let recordingFile = recordingFile else {
//            return nil
//        }
//        
//        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//        let exportURL = documentsPath.appendingPathComponent("export.m4a")
//        
//        try? FileManager.default.removeItem(at: exportURL)
//        
//        let asset = AVURLAsset(url: recordingFile.url)
//        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
//            return nil
//        }
//        
//        try await exportSession.export(to: exportURL, as: .m4a)
//        
//        return exportURL
//    }
//    
//    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
//        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
//        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
//        let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
//        // Amplification pour l'affichage
//        let amplifiedRMS = min(rms * 5.0, 1.0) // Multiplie par 5 et plafonne à 1.0
//        
//        return amplifiedRMS
//    }
//}
