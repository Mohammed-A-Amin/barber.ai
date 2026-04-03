//
//  SplashScreenView.swift
//  hairapp
//
//  Created by Fahim Rashid on 8/22/24.
//

import SwiftUI

struct SplashScreenView: View {
    var body: some View {
        // Z stack is putting this in front of all the content
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            Text("barber.ai").font(.title).foregroundColor(.white)
        }
    }
}

#Preview {
    SplashScreenView()
}
