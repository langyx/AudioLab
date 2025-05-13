//
//  AudioLabApp.swift
//  AudioLab
//
//  Created by Yannis Lang on 09/05/2025.
//

import SwiftUI

@main
struct AudioLabApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("StudioView", systemImage: "") {
                    StudioView()
                }
                Tab("AudioLoopBackView", systemImage: "") {
                    AudioLoopBackView()
                }
            }
        }
    }
}
