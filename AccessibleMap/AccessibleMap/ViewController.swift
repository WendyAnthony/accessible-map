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
    @IBOutlet var zoomInButton: UIButton!
    @IBOutlet var zoomOutButton: UIButton!
    
    var routeTask:AGSRouteTask = AGSRouteTask(url: URL(string: "https://route.arcgis.com/arcgis/rest/services/World/Route/NAServer/Route_NorthAmerica")!)
    var routeParameters:AGSRouteParameters?
    var generatedRoute:AGSRoute?
    var stopGraphicsOverlay = AGSGraphicsOverlay()
    var routeGraphicsOverlay = AGSGraphicsOverlay()

    private var map: AGSMap!
    private var featureTable: AGSServiceFeatureTable!
    private var featureLayer: AGSFeatureLayer!
    private var graphicsOverlayer: AGSGraphicsOverlay!
    private var locatorTask: AGSLocatorTask!
    private var reverseGeocodeParameters: AGSReverseGeocodeParameters!
    private var cancelable: AGSCancelable!
    
    private var pointsFeatureTable: AGSServiceFeatureTable!
    private var buildingsFeatureTable: AGSServiceFeatureTable!
    private var naturalAreaFeatureTable: AGSServiceFeatureTable!
    
    private var welcomeText = ""
    
    private let POINTS_FEATURE_SERVICE_URL = URL(string: "http://services.arcgis.com/Wl7Y1m92PbjtJs5n/ArcGIS/rest/services/Downtown_Redlands/FeatureServer/1")!
    private let NATURAL_AREA_FEATURE_SERVICE_URL = URL(string: "http://services.arcgis.com/Wl7Y1m92PbjtJs5n/ArcGIS/rest/services/Downtown_Redlands/FeatureServer/7")!
    private let LOCATOR_URL = URL(string: "https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer")!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        map = AGSMap(basemap: AGSBasemap.streetsNightVector())

        mapView.map = map
        
        graphicsOverlayer = AGSGraphicsOverlay()
        mapView.graphicsOverlays.add(graphicsOverlayer)
        
        locatorTask = AGSLocatorTask(url: LOCATOR_URL)
        reverseGeocodeParameters = AGSReverseGeocodeParameters()
        reverseGeocodeParameters.resultAttributeNames = ["Address", "Neighborhood"]
        reverseGeocodeParameters.maxResults = 1
        
        mapView.touchDelegate = self
        mapView.callout.delegate = self
        
        pointsFeatureTable = AGSServiceFeatureTable(url: POINTS_FEATURE_SERVICE_URL)
        naturalAreaFeatureTable = AGSServiceFeatureTable(url: NATURAL_AREA_FEATURE_SERVICE_URL)
        
        // callout set up
        mapView.callout.isAccessoryButtonHidden = false
        mapView.callout.accessoryButtonImage = UIImage(named: "navigate_icon")
        for v in mapView.callout.subviews as [UIView] {
            // set title of callout accessory button for voiceover
            if let btn = v as? UIButton {
                btn.setTitle("navigate button", for: UIControlState.normal)
            }
        }
        
        // accessibility
        mapView.accessibilityLanguage = "en-US"
        view.accessibilityElements = [mapView, zoomInButton, zoomOutButton, mapView.callout, mapView.callout.subviews]
        
        // turn off pan/zoom/rotate gestures
        mapView.interactionOptions.isEnabled = false
        
        // work around
        addUserLocation()
        
        // get default routing parameters
        routeTask.credential = AGSCredential(user: "user", password: "password")
        routeTask.load { [weak self] (error) in
            if let error = error {
                print(error)
            }
            self?.getDefaultParameters()
        }
        
        //add graphicsOverlays to the map view
        mapView.graphicsOverlays.addObjects(from: [routeGraphicsOverlay, stopGraphicsOverlay])

    }
    
    func addUserLocation() {
        let userLocation = AGSPoint(x: -117.182, y: 34.0564, spatialReference: AGSSpatialReference.wgs84())
        let userLocation_webmercator = AGSGeometryEngine.projectGeometry(userLocation, to: AGSSpatialReference.webMercator()) as! AGSPoint
        let symbol = AGSPictureMarkerSymbol(image: UIImage(named: "person_location")!)
        symbol.height = 30.0
        symbol.width = 30.0
        let graphic = AGSGraphic(geometry: userLocation_webmercator, symbol: symbol, attributes: nil)
        graphicsOverlayer.graphics.add(graphic)
        
        mapView.setViewpoint(AGSViewpoint(center: userLocation, scale: 3000))
        
        
        // get current location address after a delay to allow spoken text to finish
        unowned let unownedSelf = self
        let delay = DispatchTime.now() + .seconds(3)
        DispatchQueue.main.asyncAfter(deadline: delay, execute: {
            unownedSelf.getAddress(of: userLocation_webmercator)
        })
    }
    
    func getAddress(of location: AGSPoint) {
        //cancel previous request
        if cancelable != nil {
            cancelable.cancel()
        }
        
        //normalize point
        let normalizedPoint = AGSGeometryEngine.normalizeCentralMeridian(of: location) as! AGSPoint
        
        //reverse geocode
        cancelable = locatorTask.reverseGeocode(withLocation: normalizedPoint, parameters: self.reverseGeocodeParameters) { [weak self] (results: [AGSGeocodeResult]?, error: Error?) -> Void in
            if let error = error as NSError? {
                if error.code != NSUserCancelledError { //user canceled error
                    print(error.localizedDescription)
                }
            }
            else {
                if let results = results , results.count > 0 {
                    let addr = results.first!.attributes!["Address"]!
                    let neighborhood = results.first!.attributes!["Neighborhood"]!
                    let text = "You are located at \(addr) in \(neighborhood). "
                    self?.welcomeText.append(text)
                    self?.queryFeatures(around: normalizedPoint, within: 200)
                    return
                }
                else {
                    print("No address found")
                }
            }
        }
    }
    
    func queryFeatures(around location: AGSPoint, within distance: Double) {
        let area = AGSGeometryEngine.bufferGeometry(location, byDistance: distance)
        let dispatchGroup = DispatchGroup()
        var totalCount = 0
        
        var pointsFeatures = [AGSFeature]()
        
        dispatchGroup.enter()
        let pointsQP = AGSQueryParameters()
        pointsQP.whereClause = "type in ('pub', 'restaurant', 'library', 'place_of_worship', 'fast_food')"
        pointsQP.geometry = area
        pointsFeatureTable.queryFeatures(with: pointsQP) { (result:AGSFeatureQueryResult?, error:Error?) in
            guard error == nil else {
                print("error: \(error!.localizedDescription)")
                return
            }
            if let features = result?.featureEnumerator().allObjects {
                if features.count > 0 {
                    totalCount += features.count
                    pointsFeatures.append(contentsOf: features)
                }
            }
            dispatchGroup.leave()
        }
        
        dispatchGroup.enter()
        let naturalAreaQP = AGSQueryParameters()
        naturalAreaQP.geometry = area
        naturalAreaFeatureTable.queryFeatures(with: pointsQP) { (result:AGSFeatureQueryResult?, error:Error?) in
            guard error == nil else {
                print("error: \(error!.localizedDescription)")
                return
            }
            if let features = result?.featureEnumerator().allObjects {
                if features.count > 0 {
                    totalCount += features.count
                }
            }
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: DispatchQueue.main) { [weak self] in
            if let weakSelf = self {
                weakSelf.welcomeText.append("There are \(totalCount) point of interests within a distance of 3000 meters.")
                UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, "\(weakSelf.welcomeText)")
                
                weakSelf.addOperationLayers(with: pointsFeatures)
            }
            
        }
    }
    
    func addOperationLayers(with selectedFeatures: [AGSFeature]) {
        featureTable = AGSServiceFeatureTable(url: POINTS_FEATURE_SERVICE_URL)
        featureLayer = AGSFeatureLayer(featureTable: featureTable)
        featureLayer.definitionExpression = "type in ('restaurant')"
        featureLayer.setFeatures(selectedFeatures, visible: true)
        
        let renderer = AGSSimpleRenderer()
        let restaurantSymbol = AGSPictureMarkerSymbol(image: UIImage(named: "food_plate")!)
        renderer.symbol = restaurantSymbol
        featureLayer.renderer = renderer
        
        map.operationalLayers.add(featureLayer)
    }
    
    // get user's current location - not in use
    // reason - location data from GPX file did not work for simulation
    
    func startLocationDisplay() {
        let gpxDataSource = AGSGPXLocationDataSource(name: "Location")
        mapView.locationDisplay.dataSource = gpxDataSource
        
        mapView.locationDisplay.autoPanMode = .recenter
        mapView.locationDisplay.showPingAnimationSymbol = true
        
        mapView.locationDisplay.start {(error:Error?) -> Void in
            guard error == nil else {
                print("\(error!.localizedDescription)")
                return
            }
        }
    }
    
    // get zoom level from current map scale
    
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
        mapView.setViewpoint(viewpoint) { [weak self](true) in
            guard let currentViewpoint = self?.mapView.currentViewpoint(with: AGSViewpointType.centerAndScale),
                !currentViewpoint.targetScale.isNaN else {
                    //no viewpoint/targetScale yet
                    return
            }
            let zoomLevel = self?.getZoomLevel(of: currentViewpoint.targetScale)
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, "Zoom \(zoomLevel!)")
        }
    }
    
    @IBAction func zoomIn(_ sender: Any) {
        guard let currentExtent = mapView.currentViewpoint(with: .boundingGeometry)?.targetGeometry as? AGSEnvelope else {
            //no viewpoint extent
            return
        }
        
        let zoomedExtent = currentExtent.toBuilder().expand(byFactor: 0.5).toGeometry()
        let viewpoint = AGSViewpoint(targetExtent: zoomedExtent)
        mapView.setViewpoint(viewpoint) { [weak self](true) in
            guard let currentViewpoint = self?.mapView.currentViewpoint(with: AGSViewpointType.centerAndScale),
                !currentViewpoint.targetScale.isNaN else {
                    //no viewpoint/targetScale yet
                    return
            }
            let zoomLevel = self?.getZoomLevel(of: currentViewpoint.targetScale)
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, "Zoom \(zoomLevel!)")
        }
    }
}

extension ViewController: AGSGeoViewTouchDelegate, AGSCalloutDelegate {
    
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
        
        let destinationGraphic = AGSGraphic(geometry: endLocation, symbol: stopSymbol(), attributes: nil)
        
        stopGraphicsOverlay.graphics.removeAllObjects()
        stopGraphicsOverlay.graphics.add(destinationGraphic)
        
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
        
        // Find the "Walking Distance" travel mode
        
        if let travelMode = (routeTask.routeTaskInfo().travelModes.filter { $0.name == "Walking Distance" }).first {
            parameters.travelMode = travelMode
            print("using travel mode: \(travelMode.name)")
        }
        
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
                
                print("routed completed, no error")
                self?.generatedRoute = route
                let routeGraphic = AGSGraphic(geometry: route.routeGeometry, symbol: self?.routeSymbol(), attributes: nil)
                self?.routeGraphicsOverlay.graphics.add(routeGraphic)
                
                var directions = "Directions to your destination, "
                for maneuver in route.directionManeuvers {
                    directions.append(", " + maneuver.directionText)
                }
                UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, directions)
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
        let symbol = AGSSimpleLineSymbol(style: .solid, color: .green, width: 5)
        return symbol
    }
    
    //method provides a marker symbol for stop
    func stopSymbol() -> AGSMarkerSymbol {
        guard let image = UIImage(named: "destination_icon") else {
            // could not find default image, return simple marker instead
            return AGSSimpleMarkerSymbol(style: .circle, color: .red, size: 24.0)
        }
        let marker = AGSPictureMarkerSymbol(image: image)
        
        // offset the marker a bit so the flag pole is on the destination
        marker.offsetX = image.size.width / 4
        marker.offsetY = image.size.height / 4
        return marker
    }

    // MARK: - AGSGeoViewTouchDelegate
    
    func geoView(_ geoView: AGSGeoView, didTapAtScreenPoint screenPoint: CGPoint, mapPoint: AGSPoint) {
        
        /*
        // show the callout with the attributes of the tapped feature
        // identifyLayer did not work when VoiceOver is ON, query result is always 0
        let tolerance:Double = 20
        mapView.identifyLayer(featureLayer, screenPoint: screenPoint, tolerance: tolerance, returnPopupsOnly: false) { [weak self] (result) in
            if result.geoElements.count > 0 && self?.mapView.callout.isHidden == true {
                self?.mapView.callout.title = result.geoElements[0].attributes.object(forKey: "type") as? String
                self?.mapView.callout.detail = result.geoElements[0].attributes.object(forKey: "name") as? String
                self?.mapView.callout.show(at: mapPoint, screenOffset: CGPoint.zero, rotateOffsetWithMap: false, animated: true)
            } else { // hide the callout
                self?.mapView.callout.dismiss()
            }
        }
        */
        
        // temporary workaround
        
        if mapView.callout.isHidden == false {
            return
        }
        
        view.accessibilityElements = [mapView.callout.subviews]
        
        let selectedGeometry = AGSPoint(x: -13044594.483900, y: 4036478.673700, spatialReference: AGSSpatialReference.webMercator())
        mapView.callout.title = "Tartan"
        mapView.callout.detail = "Restaurant"
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, "You have selected \(mapView.callout.title!) \(mapView.callout.detail!). Tap to navigate.")
       
        mapView.callout.show(at: selectedGeometry, screenOffset: CGPoint.zero, rotateOffsetWithMap: false, animated: true)
        view.accessibilityElements = [mapView, mapView.subviews, mapView.callout.subviews]
    }
    
    // MARK: - AGSCalloutDelegate
    
    func didTapAccessoryButton(for callout: AGSCallout) {
        
        // hide the callout
        mapView.callout.dismiss()
        
        var spokenString = "Navigating you to "
        if let title = callout.title {
            spokenString.append(title)
        }
        if let detail = callout.detail {
            spokenString.append(detail)
        }
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, spokenString)
        
        view.accessibilityElements = [mapView, zoomInButton, zoomOutButton, mapView.callout, mapView.callout.subviews]
        
        // because we're not out in Redlands, we're hardcoding the user location
        // also, because of potential mapView issues with VoiceOver, we're not getting the destination correctly
//        guard let currentLocation = mapView.locationDisplay.mapLocation,
//            let destination = (callout.representedObject as? AGSGraphic)?.geometry as? AGSPoint else {
//            print("no current location")
//            return
//        }
        
        let userLocation = AGSPoint(x: -117.182, y: 34.056, spatialReference: AGSSpatialReference.wgs84())
        let selectedGeometry = AGSPoint(x: -13044594.483900, y: 4036478.673700, spatialReference: AGSSpatialReference.webMercator())

        // add code to start navigation
        // route after a delay to allow previous spokenText to finish
        
        unowned let unownedSelf = self
        let delay = DispatchTime.now() + .seconds(3)
        DispatchQueue.main.asyncAfter(deadline: delay, execute: {
            unownedSelf.route(userLocation, endLocation: selectedGeometry)
            
        })
    }
}

