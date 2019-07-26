//
//  ViewController.swift
//  ARAffermations
//
//  Created by Ari on 7/16/18.
//  Copyright © 2018 Logical Nonsense. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import MultipeerConnectivity

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, SelectTableViewControllerDelegate {
    // MARK: - IBOutlets
    @IBOutlet var mapWorldButton: UIButton!
    @IBOutlet var addButton: UIBarButtonItem!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet var sessionInfoView: UIView!
    @IBOutlet weak var sceneView: ARSCNView!
    
    //MARK: Affermation Variables
    var selectedAffermation: String?
    
    // MARK: - View Life Cycle
    var multipeerSession: MultipeerSession!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        multipeerSession = MultipeerSession(receivedDataHandler: receivedData)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        guard ARWorldTrackingConfiguration.isSupported else {
            fatalError("""
                ARKit is not available on this device. For apps that require ARKit
                for core functionality, use the `arkit` key in the key in the
                `UIRequiredDeviceCapabilities` section of the Info.plist to prevent
                the app from installing. (If the app can't be installed, this error
                can't be triggered in a production scenario.)
                In apps where AR is an additive feature, use `isSupported` to
                determine whether to show UI for launching AR experiences.
            """) // For details, see https://developer.apple.com/documentation/arkit
        }
        
        // Start the view's AR session.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration)
        
        // Set a delegate to track the number of plane anchors for providing UI feedback.
        sceneView.session.delegate = self
        
        sceneView.debugOptions = []
        // Prevent the screen from being dimmed after a while as users will likely
        // have long periods of interaction without touching the screen or buttons.
        UIApplication.shared.isIdleTimerDisabled = true
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's AR session.
        sceneView.session.pause()
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // Render the AR anchor for the screen
        if let anchorName = anchor.name {
            node.addChildNode(createNewBubbleParentNode(anchorName))
        }
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        switch frame.worldMappingStatus {
        case .notAvailable:
            //disables users from adding an affermation hen an AR scene is not avaliable
            self.addButton.isEnabled = false
        case .limited, .extending, .mapped:
            self.addButton.isEnabled = true
        @unknown default:
            break
        }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }
    
    // MARK: - ARSessionObserver
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay.
        sessionInfoLabel.text = "Session was interrupted"
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required.
        sessionInfoLabel.text = "Session interruption ended"
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        sessionInfoLabel.text = "Session failed: \(error.localizedDescription)"
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetTracking(nil)
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    // MARK: - Multiuser shared session
    
    @IBAction func handleSceneTap(_ sender: UITapGestureRecognizer) {
        if selectedAffermation != nil && selectedAffermation != ""{
            // Hit test to find a place for a virtual object.
            guard let hitTestResult = sceneView
                .hitTest(sender.location(in: sceneView), types: [.existingPlaneUsingGeometry, .estimatedHorizontalPlane, .featurePoint, .existingPlane, .estimatedVerticalPlane, .existingPlaneUsingExtent])
                .first
                else { return }
            
            // Place an anchor for a virtual character. The model appears in renderer(_:didAdd:for:).
            let anchor = ARAnchor(name: selectedAffermation!, transform: hitTestResult.worldTransform)
            sceneView.session.add(anchor: anchor)
            selectedAffermation = nil
            
            // Send the anchor info to peers, so they can place the same content.
            guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
                else { fatalError("can't encode anchor") }
            self.multipeerSession.sendToAllPeers(data)
        }
    }
    
    @IBAction func shareSession(_ button: UIButton) {
        sceneView.session.getCurrentWorldMap { worldMap, error in
            guard let map = worldMap
                else { print("Error: \(error!.localizedDescription)"); return }
            guard let data = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                else { fatalError("can't encode map") }
            self.multipeerSession.sendToAllPeers(data)
        }
    }
    
    var mapProvider: MCPeerID?
    
    func receivedData(_ data: Data, from peer: MCPeerID) {
        
        do {
            if let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) {
                // Run the session with the received world map.
                let configuration = ARWorldTrackingConfiguration()
                configuration.planeDetection = .horizontal
                configuration.initialWorldMap = worldMap
                sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
                
                // Remember who provided the map for showing UI feedback.
                mapProvider = peer
            }
            else
                if let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARAnchor.self, from: data) {
                    // Add anchor to the session, ARSCNView delegate adds visible content.
                    sceneView.session.add(anchor: anchor)
                }
                else {
                    print("unknown data recieved from \(peer)")
            }
        } catch {
            print("can't decode data recieved from \(peer)")
        }
    }
    
    // MARK: - AR session management
    
    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // Update the UI to provide feedback on the state of the AR experience.
        let message: String
        switch trackingState {
        case .normal where frame.anchors.isEmpty && multipeerSession.connectedPeers.isEmpty:
            // No planes detected; provide instructions for this app's AR interactions.
            message = "Move around to map the environment, or wait to join a shared session."
            
        case .normal where !multipeerSession.connectedPeers.isEmpty && mapProvider == nil:
            let peerNames = multipeerSession.connectedPeers.map({ $0.displayName }).joined(separator: ", ")
            message = "Connected with \(peerNames)."
            
        case .notAvailable:
            message = "Tracking unavailable."
            
        case .limited(.excessiveMotion):
            message = "Tracking limited - Move the device more slowly."
            
        case .limited(.insufficientFeatures):
            message = "Tracking limited - Point the device at an area with visible surface detail, or improve lighting conditions."
            
        case .limited(.initializing) where mapProvider != nil,
             .limited(.relocalizing) where mapProvider != nil:
            message = "Received map from \(mapProvider!.displayName)."
            
        case .limited(.relocalizing):
            message = "Resuming session — move to where you were when the session was interrupted."
            
        case .limited(.initializing):
            message = "Initializing AR session."
            
        default:
            // Asks a user to add a affermation or set one in the scene if one has been selected
            if (selectedAffermation != nil && selectedAffermation != ""){
                message = "Tap where you'd like to place your affermation."
                sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
            } else {
                message = ""
                sceneView.debugOptions = []
            }
        }
        
        sessionInfoLabel.text = message
        sessionInfoLabel.sizeToFit()
        sessionInfoView.isHidden = message.isEmpty
    }
    
    
    @IBAction func resetTracking(_ sender: UIButton?) {
        // Clears all nodes in AR scene and asks the user if that is okay to do before it happens
        let alert = UIAlertController(title: "Hold up!", message: "Are you sure you want to clear all affermations in this AR world?", preferredStyle: .alert)
        let yesAction = UIAlertAction(title: "Yes", style: .default) { (action) in
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = .horizontal
            self.sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
        let noAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alert.addAction(yesAction)
        alert.addAction(noAction)
        self.present(alert, animated: true)
    }
    
    // MARK: - AR session management
    func createNewBubbleParentNode(_ text : String) -> SCNNode {
        
        // Sets text billboard constraint
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.Y
        
        // Sets text bubble
        let bubble = SCNText(string: text, extrusionDepth: CGFloat(0.01))
        let font = UIFont.systemFont(ofSize: 0.15)
        bubble.font = font
        bubble.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        bubble.firstMaterial?.diffuse.contents = UIColor(displayP3Red: (250.0/255.0), green: (184.0/255.0), blue: (4.0/255.0), alpha: 1.0)
        bubble.firstMaterial?.specular.contents = UIColor.white
        bubble.firstMaterial?.isDoubleSided = true
        bubble.chamferRadius = CGFloat(0.01)
        
        // Sets bubble node
        let (minBound, maxBound) = bubble.boundingBox
        let bubbleNode = SCNNode(geometry: bubble)
        bubbleNode.pivot = SCNMatrix4MakeTranslation( (maxBound.x - minBound.x)/2, minBound.y, 0.01/2)
        bubbleNode.scale = SCNVector3Make(0.2, 0.2, 0.2)
        
        // Sets parent bubble node
        let bubbleNodeParent = SCNNode()
        bubbleNodeParent.addChildNode(bubbleNode)
        bubbleNodeParent.constraints = [billboardConstraint]
        
        return bubbleNodeParent
    }
    
    // MARK: - Select Table View Controller Delegate Methods
    
    func selectAffermation(_ affermation: String) {
        self.selectedAffermation = affermation
    }
    
    // MARK: - Navigation
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "toSelect"{
            let dvc = segue.destination as? SelectTableViewController
            dvc?.delegate = self
        }
    }
    
}

