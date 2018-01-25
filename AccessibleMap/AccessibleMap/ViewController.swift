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
    
    private var map: AGSMap!
    private var featureTable: AGSServiceFeatureTable!
    private var featureLayer: AGSFeatureLayer!
    
    private let FEATURE_SERVICE_URL = URL(string: "https://services.arcgis.com/Wl7Y1m92PbjtJs5n/ArcGIS/rest/services/Downtown_Redlands/FeatureServer/1")!
    private let GPX_FILE_NAME = "Location"
    
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
        
        map.load { [weak self] (error) in
            guard error == nil else {
                print("Error occurred when loading map: \(error!.localizedDescription)")
                return
            }
            
            // zoom to user location
            self?.startLocationDisplay()
        }
        
        addOperationLayers()
    }
    
    func addOperationLayers() {
        // need to modify code to add features that are within 1 mile radius
        
        featureTable = AGSServiceFeatureTable(url: FEATURE_SERVICE_URL)
        featureLayer = AGSFeatureLayer(featureTable: featureTable)
        featureLayer.definitionExpression = "type in ('restaurant')"
        
        let renderer = AGSSimpleRenderer()
        let restaurantSymbol = AGSPictureMarkerSymbol(image: UIImage(named: "food_plate")!)
        renderer.symbol = restaurantSymbol
        featureLayer.renderer = renderer
        
        map.operationalLayers.add(featureLayer)
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
    
    
    // reading data from GPX file: https://stackoverflow.com/questions/38507289/swift-how-to-read-coordinates-from-a-gpx-file
    
    func readDataFromFile() {
        let filePath = getFilePath(fileName: GPX_FILE_NAME)
        guard filePath != nil else {
            print ("File \"\(GPX_FILE_NAME).gpx\" does not exist in the project.")
            return
        }
        
        // setup the parser and initialize it with the filepath's data
        let data = NSData(contentsOfFile: filePath!)
        let parser = XMLParser(data: data! as Data)
        parser.delegate = self
        
        // parse the data, here the file will be read
        let success = parser.parse()
        
        // log an error if the parsing failed
        if !success {
            print ("Failed to parse the following file: \(GPX_FILE_NAME).gpx")
        }
    }
    
    func getFilePath(fileName: String) -> String? {
        // generate a computer readable path
        return Bundle.main.path(forResource: fileName, ofType: "gpx")
    }
    
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
        // only check for the lines that have a <trkpt> or <wpt> tag. The other lines don't have coordinates and thus don't interest us
        if elementName == "trkpt" || elementName == "wpt" {
            // create map coordinate from the file
            let x = attributeDict["x"]!
            let y = attributeDict["y"]!
            
            print(x, y)
        }
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

