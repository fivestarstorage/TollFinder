import SwiftUI
import MapKit
import CoreLocation
import Combine
import ToastifySwift
import Shimmer

struct RouteStop: Identifiable, Codable {
    let id = UUID()
    let latitude: Double
    let longitude: Double
    let address: String
    let order: Int
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    init(coordinate: CLLocationCoordinate2D, address: String, order: Int) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.address = address
        self.order = order
    }
}

struct TollPrice: Codable {
    let typeA: Double
    let typeB: Double
    
    init(typeA: Double, typeB: Double) {
        self.typeA = typeA
        self.typeB = typeB
    }
}

enum CarType: String, CaseIterable, Codable {
    case typeA = "Car"
    case typeB = "Truck/Van"
    
    var displayName: String {
        return self.rawValue
    }
}

struct Route: Identifiable, Codable {
    let id = UUID()
    let stops: [RouteStop]
    let tollPrice: TollPrice
    let totalDistance: Double
    let estimatedDuration: TimeInterval
    let createdAt: Date
    
    var orderedStops: [RouteStop] {
        return stops.sorted { $0.order < $1.order }
    }
    
    var startLocation: RouteStop? {
        return orderedStops.first
    }
    
    var endLocation: RouteStop? {
        return orderedStops.last
    }
    
    func getTollPrice(for carType: CarType) -> Double {
        switch carType {
        case .typeA:
            return tollPrice.typeA
        case .typeB:
            return tollPrice.typeB
        }
    }
    
    init(stops: [RouteStop], tollPrice: TollPrice, totalDistance: Double = 0, estimatedDuration: TimeInterval = 0) {
        self.stops = stops
        self.tollPrice = tollPrice
        self.totalDistance = totalDistance
        self.estimatedDuration = estimatedDuration
        self.createdAt = Date()
    }
}

struct MapView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var stopAddresses: [String] = ["", ""]
    @State private var showingAddressInput = false
    @State private var activeField: ActiveField?
    @State private var searchResults: [MKMapItem] = []
    @State private var currentRoute: Route?
    @State private var selectedCarType: CarType = .typeA
    @State private var allStops: [RouteStop] = []
    @State private var mapAnnotations: [StopAnnotation] = []
    @StateObject var toastManager = ToastManager()
    @State private var isMapLocked = false
    @State private var routeOverlays: [MKPolyline] = []
    @StateObject private var tollCalculator = TollCalculatorViewModel()
    
    enum ActiveField: Hashable {
        case stop(Int)
    }
    
    var body: some View {
        ZStack {
        MapViewWithPolylines(
            region: $region,
            isMapLocked: isMapLocked,
            annotations: mapAnnotations,
            polylines: routeOverlays
        )
        .ignoresSafeArea()
        .overlay(
            ShimmeringRoutesOverlay(region: $region, polylines: routeOverlays)
                .allowsHitTesting(false)
        )
            
            VStack {
                Spacer()
                
                Button(action: {
                    print("Find Tolls button pressed - current stops: \(allStops.count)")
                    frameAllStopsAndLock()
                    showingAddressInput = true
                }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                        Text("Find Tolls")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.black)
                    .cornerRadius(8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 34)
            }
        }
        .onAppear {
            locationManager.requestLocationPermission()
        }
        .onChange(of: locationManager.userLocation) {
            if let location = locationManager.userLocation {
                region.center = location.coordinate
            }
        }
        .sheet(isPresented: $showingAddressInput, onDismiss: {
            unlockMap()
        }) {
            AddressInputSheet(
                stopAddresses: $stopAddresses,
                activeField: $activeField,
                searchResults: $searchResults,
                userLocation: locationManager.userLocation,
                allStops: $allStops,
                onLocationSelected: selectLocation,
                onUseCurrentLocation: useCurrentLocation,
                onAddStop: addStop,
                onFindTolls: searchForTolls,
                onRemoveStop: { index in
                    removeStop(at: index)
                },
                onStopsReordered: {
                    updateMapAnnotations()
                    frameAllStops()
                }
            )
        }
        .toastify(using: toastManager)
    }
    
    private func centerOnUserLocation() {
        if let userLocation = locationManager.userLocation {
            withAnimation(.easeInOut(duration: 0.5)) {
                region.center = userLocation.coordinate
            }
        }
    }
    
    private func searchForTolls() {
        let validStops = allStops.filter { !$0.address.isEmpty }
        guard validStops.count >= 2 else { return }
        
        let tollPrice = calculateTollPrice(for: validStops)
        currentRoute = Route(stops: validStops, tollPrice: tollPrice)
        showingAddressInput = false
        
        print("Route created with \(validStops.count) stops")
        print("Toll price - Car: $\(tollPrice.typeA), Truck: $\(tollPrice.typeB)")
        
        Task {
            await tollCalculator.calculateTollsForRoute(stops: validStops)
        }
    }
    
    private func getCoordinateFromAddress(_ address: String) -> CLLocationCoordinate2D? {
        return region.center
    }
    
    private func calculateTollPrice(for stops: [RouteStop]) -> TollPrice {
        let basePrice = Double(stops.count - 1) * 5.0
        return TollPrice(
            typeA: basePrice,
            typeB: basePrice * 1.5
        )
    }
    
    private func addStop() {
        if stopAddresses.count >= 5 {
            toastManager.show(toast: ToastModel(
                message: "Maximum limit reached! You can only add up to 5 stops.",
                icon: "exclamationmark.triangle.fill",
                backgroundColor: .orange,
                duration: 3.0
            ))
            return
        }
        
        stopAddresses.append("")
        activeField = .stop(stopAddresses.count - 1)
        
        updateMapAnnotations()
        frameAllStops()
    }
    
    private func removeStop(at index: Int) {
        guard stopAddresses.count > 2 else { return }
        
        stopAddresses.remove(at: index)
        
        if index < allStops.count {
            allStops.remove(at: index)
        }
        
        for i in 0..<allStops.count {
            allStops[i] = RouteStop(
                coordinate: allStops[i].coordinate,
                address: allStops[i].address,
                order: i
            )
        }
        
        updateMapAnnotations()
        frameAllStops()
    }
    
    private func getStopPlaceholder(for index: Int) -> String {
        if index == 0 {
            return "Start location"
        } else if index == stopAddresses.count - 1 {
            return "End location"
        } else {
            return "Stop \(index)"
        }
    }
    
    private func selectLocation(_ mapItem: MKMapItem) {
        let locationName = mapItem.name ?? "Unknown Location"
        let coordinate = mapItem.placemark.coordinate
        
        switch activeField {
        case .stop(let index):
            if index < stopAddresses.count {
                stopAddresses[index] = locationName
                
                let newStop = RouteStop(coordinate: coordinate, address: locationName, order: index)
                
                // Ensure allStops array is large enough
                while allStops.count <= index {
                    allStops.append(RouteStop(coordinate: region.center, address: "", order: allStops.count))
                }
                
                allStops[index] = newStop
                print("Updated stop \(index + 1): '\(locationName)' at \(coordinate.latitude), \(coordinate.longitude)")
                
                if index + 1 < stopAddresses.count {
                    activeField = .stop(index + 1)
                }
            }
            
        case .none:
            break
        }
        
        updateMapAnnotations()
        frameAllStops()
        
        searchResults = []
        
        withAnimation(.easeInOut(duration: 0.5)) {
            region.center = coordinate
        }
    }
    
    private func useCurrentLocation() {
        guard let userLocation = locationManager.userLocation else { return }
        
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(userLocation) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    let address = self.formatPlacemarkAddress(placemark)
                    let coordinate = userLocation.coordinate
                    
                    if self.activeField == nil {
                        let targetIndex = self.stopAddresses.firstIndex(where: { $0.isEmpty }) ?? (self.stopAddresses.count - 1)
                        self.activeField = .stop(targetIndex)
                    }

                    switch self.activeField {
                    case .stop(let index):
                        if index < self.stopAddresses.count {
                            self.stopAddresses[index] = address
                            
                            let newStop = RouteStop(coordinate: coordinate, address: address, order: index)
                            
                            // Ensure allStops array is large enough
                            while self.allStops.count <= index {
                                self.allStops.append(RouteStop(coordinate: self.region.center, address: "", order: self.allStops.count))
                            }
                            
                            self.allStops[index] = newStop
                            print("Updated stop \(index + 1) via current location: '\(address)' at \(coordinate.latitude), \(coordinate.longitude)")
                            
                            self.searchResults = []
                        }
                        
                    case .none:
                        break
                    }
                    self.updateMapAnnotations()
                    self.frameAllStops()
                }
            }
        }
    }
    
    private func formatPlacemarkAddress(_ placemark: CLPlacemark) -> String {
        var components: [String] = []
        
        if let streetNumber = placemark.subThoroughfare {
            components.append(streetNumber)
        }
        if let street = placemark.thoroughfare {
            components.append(street)
        }
        if let city = placemark.locality {
            components.append(city)
        }
        
        return components.isEmpty ? "Current Location" : components.joined(separator: " ")
    }
    
    private func updateMapAnnotations() {
        print("updateMapAnnotations: Creating annotations for \(allStops.count) stops")
        mapAnnotations = allStops.enumerated().map { index, stop in
            let displayTitle = stop.address.isEmpty ? "Stop \(index + 1)" : stop.address
            print("Creating annotation \(index + 1): '\(displayTitle)' at \(stop.coordinate.latitude), \(stop.coordinate.longitude)")
            return StopAnnotation(
                id: stop.id,
                coordinate: stop.coordinate,
                title: displayTitle,
                subtitle: "",
                color: .black
            )
        }
        print("updateMapAnnotations: Created \(mapAnnotations.count) annotations")
        
        generateRouteBetweenStops()
    }
    
    private func frameAllStops() {
        let validStops = allStops.filter { stop in
            let isValid = stop.coordinate.latitude != 0 && stop.coordinate.longitude != 0 && !stop.address.isEmpty
            if !isValid {
                print("Skipping invalid stop: '\(stop.address)' at \(stop.coordinate.latitude), \(stop.coordinate.longitude)")
            }
            return isValid
        }
        
        guard validStops.count >= 1 else { 
            print("frameAllStops: Not enough valid stops (\(validStops.count) out of \(allStops.count))")
            return 
        }
        
        print("frameAllStops: Framing \(validStops.count) valid stops out of \(allStops.count) total")
        for (index, stop) in validStops.enumerated() {
            print("Valid Stop \(index + 1): '\(stop.address)' at \(stop.coordinate.latitude), \(stop.coordinate.longitude)")
        }
        
        let coordinates = validStops.map { $0.coordinate }
        
        let center: CLLocationCoordinate2D
        let span: MKCoordinateSpan
        
        if validStops.count == 1 {
            center = coordinates.first!
            span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        } else {
            let minLat = coordinates.map { $0.latitude }.min() ?? 0
            let maxLat = coordinates.map { $0.latitude }.max() ?? 0
            let minLon = coordinates.map { $0.longitude }.min() ?? 0
            let maxLon = coordinates.map { $0.longitude }.max() ?? 0
            
            center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            
            span = MKCoordinateSpan(
                latitudeDelta: max(maxLat - minLat, 0.01) * 2.0,
                longitudeDelta: max(maxLon - minLon, 0.01) * 2.0
            )
        }
        
        print("frameAllStops: Setting center to \(center.latitude), \(center.longitude) with span \(span.latitudeDelta), \(span.longitudeDelta)")
        
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 1.0)) {
                self.region = MKCoordinateRegion(center: center, span: span)
            }
            print("frameAllStops: Region updated to center: \(self.region.center.latitude), \(self.region.center.longitude)")
        }
    }
    
    private func frameAllStopsAndLock() {
        frameAllStops()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            self.isMapLocked = true
            print("Map locked - interaction disabled")
        }
    }
    
    private func unlockMap() {
        isMapLocked = false
        print("Map unlocked - interaction enabled")
    }
    
    private func generateRouteBetweenStops() {
        guard allStops.count >= 2 else {
            routeOverlays = []
            return
        }
        
        let validStops = allStops.filter { stop in
            stop.coordinate.latitude != 0 && stop.coordinate.longitude != 0 && !stop.address.isEmpty
        }
        
        guard validStops.count >= 2 else {
            routeOverlays = []
            return
        }
        
        print("Generating routes between \(validStops.count) stops")
        routeOverlays = []
        
        for i in 0..<(validStops.count - 1) {
            let startStop = validStops[i]
            let endStop = validStops[i + 1]
            
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: startStop.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: endStop.coordinate))
            request.transportType = .automobile
            
            let directions = MKDirections(request: request)
            directions.calculate { response, error in
                if let error = error {
                    print("Route calculation error between stop \(i+1) and \(i+2): \(error.localizedDescription)")
                    return
                }
                
                guard let route = response?.routes.first else {
                    print("No route found between stop \(i+1) and \(i+2)")
                    return
                }
                
                DispatchQueue.main.async {
                    self.routeOverlays.append(route.polyline)
                    print("Added route segment \(i+1) -> \(i+2): \(route.distance/1000) km")
                }
            }
        }
    }
    
    private func polylineToCoordinates(_ polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let pointCount = polyline.pointCount
        let coordinates = UnsafeMutablePointer<CLLocationCoordinate2D>.allocate(capacity: pointCount)
        defer { coordinates.deallocate() }
        
        polyline.getCoordinates(coordinates, range: NSRange(location: 0, length: pointCount))
        
        return Array(UnsafeBufferPointer(start: coordinates, count: pointCount))
    }
    
    private func coordinateToPoint(_ coordinate: CLLocationCoordinate2D, in region: MKCoordinateRegion) -> CGPoint {
        let mapRect = MKMapRect.world
        let mapPoint = MKMapPoint(coordinate)
        
        let x = (mapPoint.x / mapRect.size.width) * UIScreen.main.bounds.width
        let y = (mapPoint.y / mapRect.size.height) * UIScreen.main.bounds.height
        
        return CGPoint(x: x, y: y)
    }
}

struct MapViewWithPolylines: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let isMapLocked: Bool
    let annotations: [StopAnnotation]
    let polylines: [MKPolyline]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        let currentRegion = mapView.region
        let regionChanged = abs(currentRegion.center.latitude - region.center.latitude) > 0.001 ||
                           abs(currentRegion.center.longitude - region.center.longitude) > 0.001 ||
                           abs(currentRegion.span.latitudeDelta - region.span.latitudeDelta) > 0.001 ||
                           abs(currentRegion.span.longitudeDelta - region.span.longitudeDelta) > 0.001
        if regionChanged {
            mapView.setRegion(region, animated: true)
        }

        mapView.isScrollEnabled = !isMapLocked
        mapView.isZoomEnabled = !isMapLocked
        mapView.isPitchEnabled = !isMapLocked
        mapView.isRotateEnabled = !isMapLocked
        
		let existingAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(existingAnnotations)
		mapView.removeOverlays(mapView.overlays)
		context.coordinator.polylineRenderers.removeAll()
        
        let mkAnnotations = annotations.map { stopAnnotation -> MKPointAnnotation in
            let annotation = MKPointAnnotation()
            annotation.coordinate = stopAnnotation.coordinate
            annotation.title = stopAnnotation.title
            annotation.subtitle = stopAnnotation.subtitle
            return annotation
        }
        
        if !mkAnnotations.isEmpty {
            mapView.addAnnotations(mkAnnotations)
        }
        
        if !polylines.isEmpty {
            mapView.addOverlays(polylines)
        }

        if isMapLocked {
            var rect = MKMapRect.null
            for overlay in mapView.overlays {
                rect = rect.union(overlay.boundingMapRect)
            }
            for annotation in mapView.annotations where !(annotation is MKUserLocation) {
                let point = MKMapPoint(annotation.coordinate)
                let smallRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
                rect = rect.union(smallRect)
            }
            if !rect.isNull {
                let expanded = rect.insetBy(dx: -rect.size.width * 0.1, dy: -rect.size.height * 0.1)
                let insets = UIEdgeInsets(top: 120, left: 120, bottom: 240, right: 120)
                mapView.setVisibleMapRect(expanded, edgePadding: insets, animated: true)
            }
        } else {
            if !mkAnnotations.isEmpty && polylines.isEmpty {
                var rect = MKMapRect.null
                for annotation in mapView.annotations where !(annotation is MKUserLocation) {
                    let point = MKMapPoint(annotation.coordinate)
                    let smallRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
                    rect = rect.union(smallRect)
                }
                if !rect.isNull {
                    let expanded = rect.insetBy(dx: -rect.size.width * 0.1, dy: -rect.size.height * 0.1)
                    let insets = UIEdgeInsets(top: 120, left: 120, bottom: 240, right: 120)
                    mapView.setVisibleMapRect(expanded, edgePadding: insets, animated: true)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewWithPolylines
        var polylineRenderers: [MKPolyline: MKPolylineRenderer] = [:]
        var dashPhaseTimer: Timer?
        
        init(_ parent: MapViewWithPolylines) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            
            let identifier = "StopAnnotation"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = false
            } else {
                annotationView?.annotation = annotation
            }
            
            let circleView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 12))
            circleView.backgroundColor = UIColor.black
            circleView.layer.cornerRadius = 6
            circleView.layer.shadowColor = UIColor.black.cgColor
            circleView.layer.shadowOpacity = 0.3
            circleView.layer.shadowOffset = CGSize(width: 0, height: 1)
            circleView.layer.shadowRadius = 2
            
            let titleText = (annotation.title ?? "") ?? ""
            let label = UILabel()
            label.font = UIFont.systemFont(ofSize: 11, weight: .medium)
            label.textColor = .black
            label.numberOfLines = 2
            label.textAlignment = .center
            label.text = titleText
            label.backgroundColor = .white
            label.layer.cornerRadius = 6
            label.layer.masksToBounds = true
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.3
            label.layer.shadowOffset = CGSize(width: 0, height: 1)
            label.layer.shadowRadius = 2

            let maxLabelWidth: CGFloat = 180
            let labelSize = label.sizeThatFits(CGSize(width: maxLabelWidth, height: CGFloat.greatestFiniteMagnitude))
            let paddingH: CGFloat = 8
            let paddingV: CGFloat = 4
            let labelW = min(maxLabelWidth, max(12, labelSize.width)) + paddingH * 2
            let labelH = max(14, labelSize.height) + paddingV * 2
            let dotSize: CGFloat = 12
            let spacing: CGFloat = 6
            let width = max(labelW, dotSize)
            let height = labelH + spacing + dotSize

            let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
            container.backgroundColor = .clear

            label.frame = CGRect(x: (width - labelW) / 2, y: 0, width: labelW, height: labelH)

            let dot = UIView(frame: CGRect(x: (width - dotSize) / 2, y: label.frame.maxY + spacing, width: dotSize, height: dotSize))
            dot.backgroundColor = .black
            dot.layer.cornerRadius = dotSize / 2
            dot.layer.shadowColor = UIColor.black.cgColor
            dot.layer.shadowOpacity = 0.3
            dot.layer.shadowOffset = CGSize(width: 0, height: 1)
            dot.layer.shadowRadius = 2

            container.addSubview(label)
            container.addSubview(dot)

            let renderer = UIGraphicsImageRenderer(size: container.bounds.size)
            let image = renderer.image { ctx in
                container.layer.render(in: ctx.cgContext)
            }

            annotationView?.image = image
            annotationView?.centerOffset = CGPoint(x: 0, y: -height / 2)
            
            return annotationView
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                if let existing = polylineRenderers[polyline] { return existing }
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.black.withAlphaComponent(0.25)
                renderer.lineWidth = 1.0
                renderer.lineCap = .round
                polylineRenderers[polyline] = renderer
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if !parent.isMapLocked {
                DispatchQueue.main.async {
                    self.parent.region = mapView.region
                }
            }
        }
    }
}

struct StopAnnotation: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    let color: Color
}


@MainActor
final class TollCalculatorViewModel: ObservableObject {
    struct TollLeg: Identifiable {
        let id = UUID()
        let name: String
        let amountTypeA: Double
        let amountTypeB: Double
    }

    func calculateTollsForRoute(stops: [RouteStop]) async {
        guard stops.count >= 2 else { return }
        
        for i in 0..<(stops.count - 1) {
            let a = stops[i]
            let b = stops[i + 1]
            let name = "Stop \(i + 1) -> Stop \(i + 2)"
            do {
                let resultA = try await getTollBetween(
                    origin: (a.latitude, a.longitude, "Stop \(i + 1)"),
                    destination: (b.latitude, b.longitude, "Stop \(i + 2)"),
                    vehicleClass: "A"
                )
                let resultB = try await getTollBetween(
                    origin: (a.latitude, a.longitude, "Stop \(i + 1)"),
                    destination: (b.latitude, b.longitude, "Stop \(i + 2)"),
                    vehicleClass: "B"
                )
                print("Toll \(name) — \(resultA.summary): A=$\(String(format: "%.2f", resultA.amount)) B=$\(String(format: "%.2f", resultB.amount))")
            } catch {
                print("Toll \(name): A=$0.00 B=$0.00")
            }
        }
    }

    private func getTollBetween(
        origin: (lat: Double, lng: Double, name: String),
        destination: (lat: Double, lng: Double, name: String),
        vehicleClass: String
    ) async throws -> (amount: Double, summary: String) {
        let apiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJqdGkiOiJZUVM3M2xwSkxoTlFGTk5Bb3VXYVo4MDFoeVkzSHo5Z0ZkQjJpXzRPTWFrIiwiaWF0IjoxNzU3MTM1MjY4fQ.Hb4K66Ae6wR_03Il08TeAdkbx9KK8J69D3bsL8d5zX4"

        let reqBody: [String: Any] = [
            "origin": ["lat": origin.lat, "lng": origin.lng, "name": origin.name],
            "destination": ["lat": destination.lat, "lng": destination.lng, "name": destination.name],
            "vehicleClass": vehicleClass,
            "vehicleClassByMotorway": ["CCT": vehicleClass, "ED": vehicleClass, "LCT": vehicleClass, "M2": vehicleClass, "M4": vehicleClass, "M5": vehicleClass, "M7": vehicleClass, "SHB": vehicleClass, "SHT": vehicleClass],
            "excludeToll": false,
            "includeSteps": false,
            "departureTime": ISO8601DateFormatter().string(from: Date())
        ]

        let url = URL(string: "https://api.transport.nsw.gov.au/v2/roads/toll_calc/route")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("apikey \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: reqBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return (0, "Toll calculation unavailable")
        }

        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        let routes = json?["routes"] as? [[String: Any]]
        let route = routes?.first
        let minChargeInCents = route?["minChargeInCents"] as? Double ?? 0
        let summary = route?["summary"] as? String ?? "Toll Route"
        var amount = minChargeInCents / 100.0
        if vehicleClass == "B" { amount *= 1.5 }
        return (amount, summary)
    }
}

struct ShimmeringRoutesOverlay: View {
    @Binding var region: MKCoordinateRegion
    let polylines: [MKPolyline]
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(polylines.enumerated()), id: \.offset) { _, poly in
                    let coords = polyPoints(poly)
                    if coords.count > 1 {
                        Path { path in
                            let first = mapPoint(for: coords[0], in: geo.size)
                            path.move(to: first)
                            for coord in coords.dropFirst() {
                                path.addLine(to: mapPoint(for: coord, in: geo.size))
                            }
                        }
                        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(.black.opacity(0.35))
                        .shimmering(active: true, duration: 1.4, bounce: false)
                    }
                }
            }
        }
    }
    
    private func polyPoints(_ polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let count = polyline.pointCount
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        return coords
    }
    
    private func mapPoint(for coordinate: CLLocationCoordinate2D, in size: CGSize) -> CGPoint {
        let mapRect = MKMapRect.world
        let point = MKMapPoint(coordinate)
        let x = (point.x / mapRect.size.width) * size.width
        let y = (point.y / mapRect.size.height) * size.height
        return CGPoint(x: x, y: y)
    }
}
struct AddressInputSheet: View {
    @Binding var stopAddresses: [String]
    @Binding var activeField: MapView.ActiveField?
    @Binding var searchResults: [MKMapItem]
    let userLocation: CLLocation?
    @Binding var allStops: [RouteStop]
    let onLocationSelected: (MKMapItem) -> Void
    let onUseCurrentLocation: () -> Void
    let onAddStop: () -> Void
    let onFindTolls: () -> Void
    let onRemoveStop: (Int) -> Void
    let onStopsReordered: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchTimer: Timer?
    @FocusState private var focusedField: MapView.ActiveField?
    
    private func getStopPlaceholder(for index: Int) -> String {
        return "Stop \(index + 1)"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    ForEach(0..<stopAddresses.count, id: \.self) { index in
                        stopTextField(for: index)
                    }
                    .onMove(perform: moveStops)
                    
                    Button(action: {
                        onUseCurrentLocation()
                    }) {
                        HStack {
                            Image(systemName: "location.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Use Current Location")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                    
                    if !searchResults.isEmpty {
                        ForEach(Array(searchResults.enumerated()), id: \.offset) { _, mapItem in
                            Button(action: {
                                onLocationSelected(mapItem)
                            }) {
                                HStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 20))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mapItem.name ?? "Unknown Location")
                                            .font(.system(size: 16))
                                            .foregroundColor(.black)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(getAddress(mapItem))
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .environment(\.editMode, .constant(.active))
                .listStyle(.plain)
                
                let allFilled = !stopAddresses.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                Button(action: {
                    if allFilled { onFindTolls() }
                }) {
                    HStack {
                        Image(systemName: "function")
                            .font(.system(size: 16, weight: .medium))
                        Text("Calculate Tolls")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(allFilled ? Color.black : Color.gray)
                    .cornerRadius(8)
                }
                .disabled(!allFilled)
                .padding(.horizontal, 16)
                .padding(.bottom, 34)
            }
            .navigationTitle("Plan your trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: activeField) {
                focusedField = activeField
                switch activeField {
                case .stop(let index):
                    if index < stopAddresses.count && !stopAddresses[index].isEmpty {
                        performSearch(query: stopAddresses[index])
                    }
                case .none:
                    break
                }
            }
        }
    }
    
    private var addressInputSection: some View {
        List {
            ForEach(0..<stopAddresses.count, id: \.self) { index in
                stopTextField(for: index)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .onMove(perform: moveStops)
        }
        .environment(\.editMode, .constant(.active))
        .listStyle(.plain)
    }
    
    private func stopTextField(for index: Int) -> some View {
        HStack(spacing: 8) {
            TextField(getStopPlaceholder(for: index), text: $stopAddresses[index])
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .focused($focusedField, equals: .stop(index))
                .onTapGesture {
                    activeField = .stop(index)
                }
                .onChange(of: stopAddresses[index]) {
                    activeField = .stop(index)
                    debounceSearch(query: stopAddresses[index])
                }
            
            if stopAddresses.count > 2 {
                if stopAddresses.count == 5 || index < stopAddresses.count - 1 {
                    Button(action: {
                        removeStop(at: index)
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                }
            }
            
            if index == stopAddresses.count - 1 && stopAddresses.count < 5 {
                Button(action: {
                    onAddStop()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
    }
    
    private func removeStop(at index: Int) {
        onRemoveStop(index)
    }
    
    private var addStopButton: some View {
        Button(action: {
            onAddStop()
        }) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.black)
                .frame(width: 32, height: 32)
                .background(Color.gray.opacity(0.1))
                .clipShape(Circle())
        }
        .padding(.trailing, 16)
    }
    
    private var useCurrentLocationButton: some View {
        Button(action: {
            onUseCurrentLocation()
        }) {
            HStack {
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .medium))
                Text("Use Current Location")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func debounceSearch(query: String) {
        print("Debouncing search for: '\(query)'")
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            print("Executing search for: '\(query)'")
            performSearch(query: query)
        }
    }
    
    private func moveStops(from source: IndexSet, to destination: Int) {
        var dest = destination
        if dest > stopAddresses.count { dest = stopAddresses.count }
        while allStops.count < stopAddresses.count {
            let coord = userLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            allStops.append(RouteStop(coordinate: coord, address: "", order: allStops.count))
        }
        stopAddresses.move(fromOffsets: source, toOffset: dest)
        allStops.move(fromOffsets: source, toOffset: min(dest, allStops.count))
        for i in 0..<allStops.count {
            allStops[i] = RouteStop(
                coordinate: allStops[i].coordinate,
                address: allStops[i].address,
                order: i
            )
        }
        onStopsReordered()
    }

    private func performSearch(query: String) {
        guard query.count > 2 else {
            searchResults = []
            return
        }
        
        let searchCenter = userLocation?.coordinate ?? CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(
            center: searchCenter,
            span: MKCoordinateSpan(latitudeDelta: 4.0, longitudeDelta: 4.0)
        )
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let error = error {
                print("Search error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.searchResults = []
                }
                return
            }
            
            guard let response = response else {
                DispatchQueue.main.async {
                    self.searchResults = []
                }
                return
            }
            
            DispatchQueue.main.async {
                self.searchResults = response.mapItems
                print("Search for '\(query)' returned \(response.mapItems.count) results total")
            }
        }
    }
    
    private func sortResultsByDistance(_ mapItems: [MKMapItem], userLocation: CLLocation?) -> [MKMapItem] {
        guard let userLocation = userLocation else {
            return mapItems
        }
        
        return mapItems.sorted { item1, item2 in
            let location1 = CLLocation(latitude: item1.placemark.coordinate.latitude, longitude: item1.placemark.coordinate.longitude)
            let location2 = CLLocation(latitude: item2.placemark.coordinate.latitude, longitude: item2.placemark.coordinate.longitude)
            
            let distance1 = userLocation.distance(from: location1)
            let distance2 = userLocation.distance(from: location2)
            
            return distance1 < distance2
        }
    }
    
    private func getAddress(_ mapItem: MKMapItem) -> String {
        let placemark = mapItem.placemark
        var parts: [String] = []
        
        if let street = placemark.thoroughfare {
            parts.append(street)
        }
        if let city = placemark.locality {
            parts.append(city)
        }
        if let state = placemark.administrativeArea {
            parts.append(state)
        }
        
        return parts.isEmpty ? "No address" : parts.joined(separator: ", ")
    }
    
    private func getDistanceText(_ mapItem: MKMapItem, from userLocation: CLLocation) -> String {
        let itemLocation = CLLocation(latitude: mapItem.placemark.coordinate.latitude, longitude: mapItem.placemark.coordinate.longitude)
        let distance = userLocation.distance(from: itemLocation)
        
        if distance < 1000 {
            return String(format: "%.0fm", distance)
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            break
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }
}

#Preview {
    MapView()
}