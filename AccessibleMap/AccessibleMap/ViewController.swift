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
    
    var routeTask:AGSRouteTask = AGSRouteTask(url: URL(string: "https://sampleserver6.arcgisonline.com/arcgis/rest/services/NetworkAnalysis/SanDiego/NAServer/Route")!)
    var routeParameters:AGSRouteParameters?
    var generatedRoute:AGSRoute?
    var stopGraphicsOverlay = AGSGraphicsOverlay()
    var routeGraphicsOverlay = AGSGraphicsOverlay()
    
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
        
        //add graphicsOverlays to the map view
        self.mapView.graphicsOverlays.addObjects(from: [routeGraphicsOverlay, stopGraphicsOverlay])
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
    
    // MARK: Routing
    
    //
    // route - handles routing from a starting location to an ending location
    // will display the route on the map
    // will speak the text directions when the routing completes
    //
    func route(_ startLocation: AGSPoint, endLocation: AGSPoint) {
        //route only if default parameters are fetched successfully
        guard let parameters = routeParameters else {
            print("Default route parameters not loaded")
            return
        }
        
        //set parameters to return directions
        parameters.returnDirections = true
        
        //clear previous routes
        routeGraphicsOverlay.graphics.removeAllObjects()
        
        //clear previous stops
        parameters.clearStops()
        
        //set the stops
        let stop1 = AGSStop(point: startLocation)
        stop1.name = "Origin"
        let stop2 = AGSStop(point: endLocation)
        stop2.name = "Destination"
        parameters.setStops([stop1, stop2])
        
        routeTask.solveRoute(with: parameters) { [weak self] (routeResult: AGSRouteResult?, error: Error?) -> Void in
            if let error = error {
                print(error)
            }
            else {
                //show the resulting route on the map
                //also save a reference to the route object
                //in order to access directions
                guard let route = routeResult?.routes.first else {
                    print("No route")
                    return
                }
                
                self?.generatedRoute = route
                let routeGraphic = AGSGraphic(geometry: route.routeGeometry, symbol: self?.routeSymbol(), attributes: nil)
                self?.routeGraphicsOverlay.graphics.add(routeGraphic)
            }
        }
    }
    
    //method to get the default parameters for the route task
    func getDefaultParameters() {
        routeTask.defaultRouteParameters { [weak self] (params: AGSRouteParameters?, error: Error?) -> Void in
            if let error = error {
                print(error)
            }
            else {
                //on completion store the parameters
                self?.routeParameters = params
            }
        }
    }
    
    // method provides a line symbol for the route graphic
    func routeSymbol() -> AGSSimpleLineSymbol {
        let symbol = AGSSimpleLineSymbol(style: .solid, color: UIColor.yellow, width: 5)
        return symbol
    }
}

