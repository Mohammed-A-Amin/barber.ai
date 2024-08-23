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
    @State private var selectedHairstyle: String = "Hair.usdc"
    
    let hairstyles = ["Hair.usdc", "Hair2.usdc", "Hair3.usdc"]
    
    var body: some View {
        VStack {
            ARViewContainer(useFrontCamera: $useFrontCamera, selectedHairstyle: $selectedHairstyle)
                .edgesIgnoringSafeArea(.all)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(hairstyles, id: \.self) { hairstyle in
                        Button(action: {
                            selectedHairstyle = hairstyle
                        }) {
                            Text(hairstyle)
                                .padding()
                                .background(selectedHairstyle == hairstyle ? Color.blue : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(4)
                    }
                }
            }
            .padding()
            
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
    @Binding var selectedHairstyle: String
    
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
               let hairEntity = try Entity.loadModel(named: selectedHairstyle)
               hairEntity.position = SIMD3<Float>(0, -0.17, -0.03)
               hairEntity.scale = SIMD3<Float>(0.26, 0.26, 0.26)
               let anchor = AnchorEntity(.face)
               anchor.addChild(hairEntity)
               arView.scene.addAnchor(anchor)
           } catch {
               print("Failed to load the hair model: \(error.localizedDescription)")
           }
    }
}
