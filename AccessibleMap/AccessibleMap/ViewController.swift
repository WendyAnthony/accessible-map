//
//  ViewController.swift
//  AccessibleMap
//
//  Created by Garima Dhakal on 1/25/18.
//  Copyright © 2018 Garima Dhakal. All rights reserved.
//

import UIKit
import ArcGIS

class ViewController: UIViewController {

    @IBOutlet weak var mapView: AGSMapView!
    private var map: AGSMap!
    @IBOutlet var zoomInButton: UIButton!
    @IBOutlet var zoomOutButton: UIButton!
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //map = AGSMap(basemap: AGSBasemap.openStreetMap())
        map = AGSMap(basemap: AGSBasemap.streetsVector()) //for styling
        
        mapView.map = map
        
        // accessibility
        mapView.isAccessibilityElement = true
        mapView.accessibilityLanguage = "en-US"
        
        // turn off pan/zoom/rotate gestures
        mapView.interactionOptions.isEnabled = false
        
        // activate voiceover when zoom in/out completes
        mapView.viewpointChangedHandler = { [weak self] () in
            guard let weakSelf = self else {
                return
            }
            
            if weakSelf.mapView.isNavigating == false {
                guard let currentViewpoint = weakSelf.mapView.currentViewpoint(with: AGSViewpointType.centerAndScale),
                    !currentViewpoint.targetScale.isNaN else {
                    //no viewpoint/targetScale yet
                    return
                }
                let zoomLevel = weakSelf.getZoomLevel(of: currentViewpoint.targetScale)
                UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, "Zoom \(zoomLevel)")
            }
        }
        
        // zoom to user location
        startLocationDisplay()
    }

    func startLocationDisplay() {
        mapView.locationDisplay.autoPanMode = .recenter
        mapView.locationDisplay.showPingAnimationSymbol = true
        
        mapView.locationDisplay.start {(error:Error?) -> Void in
            guard error == nil else {
                print("\(error!.localizedDescription)")
                return
            }
        }
    }
    
    func getZoomLevel(of mapScale: Double) -> Int {
        // ref. https://community.esri.com/thread/118146
        let zoom = log(591657550.500000 / (mapScale / 2)) / log(2.0)
        return Int(zoom)
    }
    
    // MARK: UI Actions
    
    @IBAction func zoomOut(_ sender: Any) {
        guard let currentExtent = mapView.currentViewpoint(with: .boundingGeometry)?.targetGeometry as? AGSEnvelope else {
            //no viewpoint extent yet
            return
        }
        
        let zoomedExtent = currentExtent.toBuilder().expand(byFactor: 2.0).toGeometry()
        let viewpoint = AGSViewpoint(targetExtent: zoomedExtent)
        mapView.setViewpoint(viewpoint, duration: 1.5, completion: nil)
    }
    
    @IBAction func zoomIn(_ sender: Any) {
        guard let currentExtent = mapView.currentViewpoint(with: .boundingGeometry)?.targetGeometry as? AGSEnvelope else {
            //no viewpoint extent
            return
        }
        
        let zoomedExtent = currentExtent.toBuilder().expand(byFactor: 0.5).toGeometry()
        let viewpoint = AGSViewpoint(targetExtent: zoomedExtent)
        mapView.setViewpoint(viewpoint, duration: 1.5, completion: nil)
    }
}

