//
//  AudioLoopBackView.swift
//  AudioLab
//
//  Created by Yannis Lang on 13/05/2025.
//

import SwiftUI

struct AudioLoopBackView: View {
    @StateObject private var audioManager = AudioLoopbackManager()
    
    var body: some View {
        VStack {
            Text("🔊 Micro vers Haut-parleur")
                .font(.headline)
                .padding()
            Text("AudioToolbox / RemoteIO")
                .font(.subheadline)
        }
    }
}

#Preview {
    AudioLoopBackView()
}
