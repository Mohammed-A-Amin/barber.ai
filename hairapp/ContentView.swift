import SwiftUI
import RealityKit
import ARKit
import Combine

struct ContentView: View {
    @State private var selectedHairstyle: String = "Hair2.usdc"
    let hairstyles = ["Hair.usdc", "Hair2.usdc", "Hair3.usdc"]
    @State private var useFrontCamera: Bool = false
    @State private var showSplash = true
    
    var body: some View {
        ZStack {
            if showSplash {
                SplashScreenView().transition(.opacity).animation(.easeOut(duration: 0.5))
            } else {
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    self.showSplash = false
                }
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @Binding var useFrontCamera: Bool
    @Binding var selectedHairstyle: String
    
    class Coordinator {
        var cancellables = Set<AnyCancellable>()
        var currentHairstyle: String = ""
        var currentCamera: Bool = false // Added to track camera state
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        updateARSession(for: arView, coordinator: context.coordinator)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Reload hair model if the selected hairstyle changes
        if context.coordinator.currentHairstyle != selectedHairstyle || context.coordinator.currentCamera != useFrontCamera {
            context.coordinator.currentHairstyle = selectedHairstyle
            context.coordinator.currentCamera = useFrontCamera
            updateARSession(for: uiView, coordinator: context.coordinator)
        }
    }
    
    private func updateARSession(for arView: ARView, coordinator: Coordinator) {
        arView.session.pause() // Pause the current session before reconfiguring
        
        if useFrontCamera {
            let config = ARFaceTrackingConfiguration()
            if ARFaceTrackingConfiguration.isSupported {
                arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
                loadHairModel(arView: arView, coordinator: coordinator)
            } else {
                print("Face tracking is not supported on this device.")
            }
        } else {
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            arView.scene.anchors.removeAll()
        }
    }
    
    private func loadHairModel(arView: ARView, coordinator: Coordinator) {
        arView.scene.anchors.removeAll() // Remove existing models
        
        Entity.loadAsync(named: selectedHairstyle)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Failed to load the hair model: \(error.localizedDescription)")
                }
            }, receiveValue: { hairEntity in
                hairEntity.position = SIMD3<Float>(0, -0.17, -0.03)
                hairEntity.scale = SIMD3<Float>(0.26, 0.26, 0.26)
                let anchor = AnchorEntity(.face)
                anchor.addChild(hairEntity)
                arView.scene.addAnchor(anchor)
            })
            .store(in: &coordinator.cancellables)
    }
}
