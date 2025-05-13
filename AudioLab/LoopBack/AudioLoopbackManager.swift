//
//  AudioLoopbackManager.swift
//  AudioLab
//
//  Created by Yannis Lang on 13/05/2025.
//

import AVFoundation
import AudioToolbox

/// Un gestionnaire qui crée une boucle audio (loopback) entre l'entrée microphone et la sortie audio.
///
/// Cette classe utilise Core Audio pour établir une connexion directe entre le microphone
/// et les haut-parleurs, permettant de rediriger l'audio capturé vers la sortie en temps réel.
class AudioLoopbackManager: ObservableObject {
    /// L'instance AudioUnit utilisée pour le traitement audio.
    var audioUnit: AudioComponentInstance?
    
    /// Initialise le gestionnaire de loopback audio.
    ///
    /// Configure la session audio et initialise l'AudioUnit nécessaire pour
    /// établir la connexion entre l'entrée et la sortie audio.
    init() {
        setupAudioSession()
        setupAudioUnit()
    }
    
    /// Configure la session audio pour permettre l'enregistrement et la lecture simultanés.
    ///
    /// Définit la catégorie de session audio sur `.playAndRecord` avec les options
    /// pour utiliser le haut-parleur par défaut et permettre les périphériques Bluetooth.
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Erreur lors de la configuration de l'AVAudioSession : \(error)")
        }
    }
    
    /// Configure l'AudioUnit pour le traitement audio en temps réel.
    ///
    /// Cette méthode:
    /// 1. Crée une description de composant audio pour le RemoteIO
    /// 2. Trouve et initialise le composant audio correspondant
    /// 3. Active l'entrée et la sortie audio
    /// 4. Configure le format audio pour l'entrée et la sortie
    /// 5. Établit la connexion entre l'entrée et la sortie via un callback de rendu
    /// 6. Initialise et démarre l'AudioUnit
    private func setupAudioUnit() {
        // Création de la description du composant audio pour RemoteIO
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                             componentSubType: kAudioUnitSubType_RemoteIO,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0,
                                             componentFlagsMask: 0)
        
        // Recherche du composant audio correspondant à la description
        guard let component = AudioComponentFindNext(nil, &desc) else {
            print("Composant Audio introuvable")
            return
        }
        
        // Création d'une nouvelle instance du composant audio
        var tempUnit: AudioComponentInstance?
        AudioComponentInstanceNew(component, &tempUnit)
        guard let unit = tempUnit else {
            print("Échec de l'initialisation de l'AudioUnit")
            return
        }
        audioUnit = unit
        
        var one: UInt32 = 1
        
        // Activation de l'entrée audio (microphone)
        // Le bus 1 correspond à l'entrée dans le contexte RemoteIO
        AudioUnitSetProperty(unit,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input,
                             1,
                             &one,
                             UInt32(MemoryLayout<UInt32>.size))
        
        // Activation de la sortie audio (haut-parleur)
        // Le bus 0 correspond à la sortie dans le contexte RemoteIO
        AudioUnitSetProperty(unit,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output,
                             0,
                             &one,
                             UInt32(MemoryLayout<UInt32>.size))
        
        // Configuration du format audio pour l'entrée et la sortie
        // Utilisation du format PCM linéaire avec des entiers signés
        var streamFormat = AudioStreamBasicDescription(
            mSampleRate: 44100,            // Fréquence d'échantillonnage en Hz
            mFormatID: kAudioFormatLinearPCM,  // Format PCM linéaire
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,            // 2 octets par paquet pour mono 16-bit
            mFramesPerPacket: 1,           // 1 frame par paquet pour PCM
            mBytesPerFrame: 2,             // 2 octets par frame pour mono 16-bit
            mChannelsPerFrame: 1,          // Audio mono (1 canal)
            mBitsPerChannel: 16,           // Résolution de 16 bits par canal
            mReserved: 0                   // Réservé, doit être 0
        )
        
        // Application du format audio à la sortie du bus d'entrée (microphone)
        AudioUnitSetProperty(unit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output,
                             1,
                             &streamFormat,
                             UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        
        // Application du format audio à l'entrée du bus de sortie (haut-parleur)
        AudioUnitSetProperty(unit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input,
                             0,
                             &streamFormat,
                             UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        
        // Configuration du callback de rendu pour connecter l'entrée à la sortie
        var callbackStruct = AURenderCallbackStruct(
            inputProc: renderCallback,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        // Enregistrement du callback sur l'entrée du bus de sortie
        AudioUnitSetProperty(unit,
                             kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input,
                             0,
                             &callbackStruct,
                             UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        
        // Initialisation et démarrage de l'AudioUnit
        AudioUnitInitialize(unit)
        AudioOutputUnitStart(unit)
    }
    
    /// Taille du buffer audio en octets.
    ///
    /// Cette valeur est utilisée comme taille de référence pour les opérations de buffer.
    let bufferByteSize: UInt32 = 512
    
    /// Callback de rendu audio appelé par Core Audio pour obtenir les données audio.
    ///
    /// Cette fonction:
    /// 1. Récupère l'instance du gestionnaire audio
    /// 2. Crée un buffer audio pour recevoir les données du microphone
    /// 3. Appelle AudioUnitRender pour obtenir les données audio du microphone
    /// 4. Copie les données audio vers le buffer de sortie
    /// 5. Libère la mémoire allouée pour le buffer temporaire
    ///
    /// - Parameters:
    ///   - inRefCon: Référence au contexte utilisateur (instance de AudioLoopbackManager)
    ///   - ioActionFlags: Drapeaux indiquant l'état de l'opération de rendu
    ///   - inTimeStamp: Horodatage des données audio
    ///   - inBusNumber: Numéro du bus audio concerné
    ///   - inNumberFrames: Nombre de frames audio à traiter
    ///   - ioData: Structure contenant les buffers de sortie à remplir
    ///
    /// - Returns: Code d'état OSStatus (noErr en cas de succès)
    private let renderCallback: AURenderCallback = { (
        inRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        ioData
    ) -> OSStatus in
        
        // Récupération de l'instance du gestionnaire audio à partir du contexte
        let audioManager = Unmanaged<AudioLoopbackManager>.fromOpaque(inRefCon).takeUnretainedValue()
        
        // Calcul de la taille du buffer en fonction du nombre de frames
        let bytesPerFrame: UInt32 = 2 // 16 bits (2 bytes) par frame
        let bufferSize = inNumberFrames * bytesPerFrame
        
        // Création d'une structure AudioBufferList pour recevoir les données du microphone
        var bufferList = AudioBufferList()
        bufferList.mNumberBuffers = 1
        bufferList.mBuffers.mNumberChannels = 1
        bufferList.mBuffers.mDataByteSize = bufferSize
        bufferList.mBuffers.mData = malloc(Int(bufferSize))
        
        // Vérification que l'allocation mémoire a réussi
        guard bufferList.mBuffers.mData != nil else {
            print("Échec d'allocation mémoire")
            return -1
        }
        
        // Obtention des données audio du microphone via AudioUnitRender
        let status = AudioUnitRender(audioManager.audioUnit!,
                                     ioActionFlags,
                                     inTimeStamp,
                                     1,
                                     inNumberFrames,
                                     &bufferList)
        
        // Vérification du statut de l'opération de rendu
        if status != noErr {
            print("Erreur AudioUnitRender: \(status)")
            free(bufferList.mBuffers.mData)
            return status
        }
        
        // Copie des données audio vers le buffer de sortie si disponible
        if let ioData = ioData {
            // Vérification que ioData est valide et a au moins un buffer
            if ioData.pointee.mNumberBuffers > 0 {
                memcpy(ioData.pointee.mBuffers.mData, bufferList.mBuffers.mData, Int(bufferList.mBuffers.mDataByteSize))
                ioData.pointee.mBuffers.mDataByteSize = bufferList.mBuffers.mDataByteSize
            }
        }
        
        // Libération de la mémoire allouée pour le buffer temporaire
        free(bufferList.mBuffers.mData)
        return noErr
    }

    /// Nettoie les ressources audio lors de la destruction de l'instance.
    ///
    /// Arrête et désinitialise l'AudioUnit pour libérer les ressources système.
    deinit {
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
        }
    }
}
