//
//  SplashScreenView.swift
//  hairapp
//
//  Created by Fahim Rashid on 8/22/24.
//

import SwiftUI

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            Text("SplashScreen").font(.title).foregroundColor(.white)
        }
    }
}

#Preview {
    SplashScreenView()
}
