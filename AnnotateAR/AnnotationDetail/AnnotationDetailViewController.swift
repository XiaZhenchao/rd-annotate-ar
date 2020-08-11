//
//  AnnotationDetailViewController.swift
//  AnnotateAR
//
//  Created by Tyler Franklin on 3/30/20.
//  Copyright © 2020 Tyler Franklin. All rights reserved.
//

import FirebaseAuth
import FirebaseFirestore
import UIKit
import ARKit
import SceneKit

class AnnotationDetailViewController: UIViewController, ARSCNViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    var viewModel: AnnotationDetailViewModel!
    var annotationIcon: UIImage!
    var collectAnnotationButtonView: UIView!
    var collectorsTableView: UITableView!
    var authorLabel: String!
    var bookLabel: String!
    var dateLabel: String!
    var pageLabel: String!
    var bodyLabel: String!

    @IBOutlet weak var takePictureButton: UIBarButtonItem!
    @IBOutlet var collectAnnotationLabel: UILabel!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!

   // private let tableViewAdapter = TableViewAdapter<User>()
    
    public override func viewDidLoad() {
        
        super.viewDidLoad()
        //self.view.backgroundColor = UIColor(patternImage: UIImage(named: "scanTargetIcon")!)
        bindViewModel()
        viewModel.ready()
        sceneView.delegate = self
        sceneView.session.delegate = self

         // Hook up status view controller callback(s).
         statusViewController.restartExperienceHandler = { [unowned self] in
             self.restartExperience()
         }
    
    }
    
    //ARView Outlets
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var blurView: UIVisualEffectView!
    
    //Camera image global variables for storage
    var cameraUIImage: UIImage!
    var cameraARRefImage: ARReferenceImage!
    
    /// The view controller that displays the status and "restart experience" UI.
    lazy var statusViewController: StatusViewController = {
        return children.lazy.compactMap({ $0 as? StatusViewController }).first!
    }()
    
    /// A serial queue for thread safety when modifying the SceneKit node graph.
    let updateQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! +
        ".serialSceneKitQueue")
    
    /// Convenience accessor for the session owned by ARSCNView.
    var session: ARSession {
        return sceneView.session
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.observeQuery()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.stopObserving()
        session.pause()
    }

    deinit {
        viewModel.stopObserving()
    }

        private func bindViewModel() {
        viewModel.didChangeData = { [weak self] data in
            guard let strongSelf = self else { return }
            
            /*
             if data.isUserACollector {
                strongSelf.disableButton()
            }
            */

            let annotation = data.annotation
            // TODO: get the user from a user id
            strongSelf.authorLabel = annotation.owner
            strongSelf.bookLabel = annotation.book
            strongSelf.bodyLabel = annotation.body
            strongSelf.pageLabel = "(p\(annotation.page))"
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short

            strongSelf.dateLabel = dateFormatter.string(from: annotation.date.dateValue())
            
            /*
            strongSelf.tableViewAdapter.update(with: data.collectors)
            strongSelf.collectorsTableView.reloadData()
            */
        }

        /*
        collectorsTableView.dataSource = tableViewAdapter
        collectorsTableView.delegate = tableViewAdapter
        activityIndicator.isHidden = true

        tableViewAdapter.cellFactory = { tableView, _, cellData in
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "cell") else { return UITableViewCell() }
            cell.textLabel?.text = cellData.userName
            return cell
        }

        let gesture = UITapGestureRecognizer(target: self, action: #selector(collectPressed))
        collectAnnotationButtonView.addGestureRecognizer(gesture)
        */

        viewModel.collectAnnotationRequestCompleted = { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.activityIndicator.isHidden = true
            strongSelf.collectAnnotationLabel.isHidden = false
 
        }

    }
    
    // Open up the camera when you click "take picture"
    @IBAction func getPicture(_ sender: UIBarButtonItem) {
        
        let imagePickerController = UIImagePickerController()

        imagePickerController.sourceType = .camera
        imagePickerController.delegate = self
        
        present(imagePickerController, animated: true, completion: nil)
    }
    
    
    // Assign the camera pic photo to global cameraImage variable
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any])
    {
        cameraUIImage = info[.originalImage] as? UIImage
        dismiss(animated: true, completion: nil)
        addARReferenceImageFromCamera()
    }
    
    // Convert CIImage to ARReferenceImage
    func addARReferenceImageFromCamera () {
        
        guard let imageToCIImage = CIImage(image: cameraUIImage),
        let cgImage = convertCIImageToCGImage(inputImage: imageToCIImage) else { return }
        let arImage = ARReferenceImage(cgImage, orientation: CGImagePropertyOrientation.up, physicalWidth: 0.22) // assuming A4 page
        
        arImage.name = "TheTextbookPage"
        cameraARRefImage = arImage
        // arConfig.trackingImages = [arImage]
    }
    
    // Convert CIImage to CGI image
    func convertCIImageToCGImage(inputImage: CIImage) -> CGImage? {
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(inputImage, from: inputImage.extent) {
            return cgImage
        }
        return nil
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Prevent the screen from being dimmed to avoid interuppting the AR experience.
        UIApplication.shared.isIdleTimerDisabled = true
        
        if cameraARRefImage != nil {
            
        // Start the AR experience
        resetTracking()
            
        } else { ("error") }
    }
    
    // MARK: - Session management (Image detection setup)
    
    /// Prevents restarting the session while a restart is in progress.
    var isRestartAvailable = true

    /// Creates a new AR configuration to run on the `session`.
    /// - Tag: ARReferenceImage-Loading
    func resetTracking() {
        
        guard let referenceImages = cameraARRefImage  else { (fatalError ("wat \(cameraARRefImage)"))
            
            /*
            ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) else { fatalError ("Missing expected asset catalog resources. \(cameraARRefImage)")
            */
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.detectionImages = [referenceImages]
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        statusViewController.scheduleMessage("Look around to detect images", inSeconds: 7.5, messageType: .contentPlacement)
    }

    private var anchorLabels = [UUID: String]()
    
    // MARK: - ARSCNViewDelegate (Image detection results)
    /// - Tag: ARImageAnchor-Visualizing
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let imageAnchor = anchor as? ARImageAnchor else { return }
        let referenceImage = imageAnchor.referenceImage
        updateQueue.async {

            
            // Create a plane to visualize the initial position of the detected image.
            let plane = SCNPlane(width: referenceImage.physicalSize.width,
                                 height: referenceImage.physicalSize.height)
            let planeNode = SCNNode(geometry: plane)
            planeNode.opacity = 0.25
            
            /*
             `SCNPlane` is vertically oriented in its local coordinate space, but
             `ARImageAnchor` assumes the image is horizontal in its local space, so
             rotate the plane to match.
             */
            planeNode.eulerAngles.x = -.pi / 2
            
            /*
             Image anchors are not tracked after initial detection, so create an
             animation that limits the duration for which the plane visualization appears.
             */
            planeNode.runAction(self.imageHighlightAction)
            
            // Add the plane visualization to the scene.
            node.addChildNode(planeNode)
            
            // Create text geometry for node
            let text = SCNText(string: self.bodyLabel, extrusionDepth: 1)
            text.font = UIFont(name: "Helvetica", size: 10)
            
            // Make a container for the text so it can wrap
            text.containerFrame = CGRect(origin:.zero, size: CGSize(width: 200, height: 100))
            text.isWrapped = true
            
            // Create textNode for notes
            let textNode = SCNNode(geometry: text)
            textNode.scale = SCNVector3(0.001,0.001,0.001)
            textNode.eulerAngles.x = -.pi / 2
            
            // Rotate textNode to align with top of planeNode instead of side
            textNode.eulerAngles.y = .pi/2
            
            // Change pivot to set textNode center to bounding box center
            let (min,max) = textNode.boundingBox
            textNode.pivot = SCNMatrix4MakeTranslation((max.x - min.x)/2,(max.y - min.y)/2, 0)
            
            // Increase text's distance from planeNode based on string size
            if self.bodyLabel.count > 100
            { textNode.position.x = textNode.position.x - 0.14}
            else
            { textNode.position.x = textNode.position.x - 0.07 }

            node.addChildNode(textNode)
        }
        

        DispatchQueue.main.async {
            let imageName = referenceImage.name ?? ""
            self.statusViewController.cancelAllScheduledMessages()
            self.statusViewController.showMessage("Detected image “\(imageName)”")
        }
    }

    var imageHighlightAction: SCNAction {
        return .sequence([
            .wait(duration: 0.25),
            .fadeOpacity(to: 0.85, duration: 0.25),
            .fadeOpacity(to: 0.15, duration: 0.25),
            .fadeOpacity(to: 0.85, duration: 0.25),
            .fadeOut(duration: 0.5),
            //.removeFromParentNode()
            
        ])
    }

    private func disableButton() {
        collectAnnotationButtonView.backgroundColor = UIColor.gray
        collectAnnotationButtonView.isUserInteractionEnabled = false
    }

    /*
     @objc func collectPressed(sender _: UITapGestureRecognizer) {
        viewModel.collectAnnotation()
        activityIndicator.isHidden = false
        collectAnnotationLabel.isHidden = true
    }
    */
}
