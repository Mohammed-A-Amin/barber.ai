//
//  ContentView.swift
//  hairapp
//
//  Created by Mohammed Amin on 8/17/24.
//

import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    @State private var useFrontCamera: Bool = true

    var body: some View {
        VStack {
            ARViewContainer(useFrontCamera: $useFrontCamera)
                .edgesIgnoringSafeArea(.all)

            Button(action: {
                useFrontCamera.toggle()
            }) {
                Text("Switch Camera")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @Binding var useFrontCamera: Bool
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        updateARSession(for: arView)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        updateARSession(for: uiView)
    }
    
    private func updateARSession(for arView: ARView) {
        arView.session.pause() // Pause the current session before reconfiguring
        
        if useFrontCamera {
            let config = ARFaceTrackingConfiguration()
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            
            loadHairModel(arView: arView)
        } else {
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            arView.scene.anchors.removeAll()
        }
    }
    
    private func loadHairModel(arView: ARView) {
        do {
               // Load the hair model from the .usdc file
               let hairEntity = try Entity.loadModel(named: "Hair.usdc")
               // Adjust the position of the hair model
               // Use a negative y-value to move the hair down
                hairEntity.position = SIMD3<Float>(0, -0.17, -0.03) // Adjust the y-value as needed
                hairEntity.scale = SIMD3<Float>(0.26, 0.26, 0.26)
               
               // Create an anchor for the hair model
               let anchor = AnchorEntity(.face)
               anchor.addChild(hairEntity)
               
               // Add the anchor to the scene
               arView.scene.addAnchor(anchor)
           } catch {
               print("Failed to load the hair model: \(error.localizedDescription)")
           }
    }
}
