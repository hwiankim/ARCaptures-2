import SwiftUI
import ARKit
import SceneKit

struct ARPreviewView: UIViewRepresentable {
    let arSession: ARCaptureSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = arSession.arSession
        view.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, ARSCNViewDelegate {
        var planeNodes: [UUID: SCNNode] = [:]

        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode,
                      for anchor: ARAnchor) {
            guard let plane = anchor as? ARPlaneAnchor else { return }
            let geo = SCNPlane(width: CGFloat(plane.planeExtent.width),
                               height: CGFloat(plane.planeExtent.height))
            geo.firstMaterial?.diffuse.contents = UIColor.green.withAlphaComponent(0.25)
            let planeNode = SCNNode(geometry: geo)
            planeNode.eulerAngles.x = -.pi / 2
            planeNode.position = SCNVector3(plane.center.x, 0, plane.center.z)
            node.addChildNode(planeNode)
            planeNodes[anchor.identifier] = planeNode
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode,
                      for anchor: ARAnchor) {
            guard let plane = anchor as? ARPlaneAnchor,
                  let planeNode = planeNodes[anchor.identifier],
                  let geo = planeNode.geometry as? SCNPlane else { return }
            geo.width = CGFloat(plane.planeExtent.width)
            geo.height = CGFloat(plane.planeExtent.height)
            planeNode.position = SCNVector3(plane.center.x, 0, plane.center.z)
        }
    }
}
