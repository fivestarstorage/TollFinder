import SwiftUI
import MapKit
import CoreLocation
import Combine
import ToastifySwift
import Shimmer
import Foundation

 

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
    @State private var shouldUnlockOnDismiss = true
    @State private var isCalculatingTolls = false
    @State private var showTollCard = false
    @State private var tollSummaryText = ""
    @State private var tollAmountA: Double = 0
    @State private var tollAmountB: Double = 0
    @State private var didFitOnce = false
    @State private var showSaveSheet = false
    @State private var savedTollName = ""
    @State private var showSaveSuccess = false
    @State private var isTollSaved = false
    @StateObject private var tollCalculator = TollCalculatorViewModel()
    @State private var routeEndpoints: [(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)] = []
    @State private var showSavedList = false
    @StateObject private var savedStore = SavedTollStore.shared
    @State private var showTopBanner = false
    @State private var topBannerMessage = ""
    @State private var topBannerColor = Color.green
    @State private var currentViewingSavedTollId: UUID? = nil
    
    enum ActiveField: Hashable {
        case stop(Int)
    }
    
    var body: some View {
        ZStack {
        MapViewWithPolylines(
            region: $region,
            isMapLocked: isMapLocked,
            annotations: mapAnnotations,
            polylines: routeOverlays,
            didFitOnce: $didFitOnce
        )
        .ignoresSafeArea()
        .overlay(
            ShimmeringRoutesOverlay(region: $region, polylines: routeOverlays, endpoints: routeEndpoints)
                .allowsHitTesting(false)
        )
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        print("Saved tolls count: \(savedStore.items.count)")
                        savedStore.items.forEach { t in
                            print("Saved toll: \(t.id.uuidString) \(t.name) A: \(String(format: "%.2f", t.totalA)) B: \(String(format: "%.2f", t.totalB))")
                        }
                        showSavedList = true
                    }) {
                        Image(systemName: "folder")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.black)
                            .padding(10)
                            .background(Color.white)
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 12)
                }
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

            if showTopBanner {
                VStack {
                    HStack {
                        Text(topBannerMessage)
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(topBannerColor)
                            .cornerRadius(8)
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showTollCard {
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Tolls Summary")
                                .font(.system(size: 18, weight: .semibold))
                            Spacer()
                            Button(action: {
                                showTollCard = false
                                isMapLocked = false
                                shouldUnlockOnDismiss = true
                                stopAddresses = ["", ""]
                                allStops = []
                                mapAnnotations = []
                                routeOverlays = []
                                currentRoute = nil
                                searchResults = []
                            }) {
                                Image(systemName: "xmark")
                                    .foregroundColor(.black)
                            }
                        }
                        Text(tollSummaryText)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        HStack {
                            Text("Class A: $\(String(format: "%.2f", tollAmountA))")
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            Text("Class B: $\(String(format: "%.2f", tollAmountB))")
                                .font(.system(size: 16, weight: .medium))
                        }
                        HStack {
                            Button(action: {
                                if isTollSaved {
                                    isTollSaved = false
                                    topBannerMessage = "Toll unsaved"
                                    topBannerColor = .orange
                                    withAnimation { showTopBanner = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { showTopBanner = false } }
                                } else {
                                    showSaveSheet = true
                                }
                            }) {
                                Image(systemName: isTollSaved ? "heart.fill" : "heart")
                                    .foregroundColor(.black)
                            }
                            Spacer()
                            Button(action: {
                                shouldUnlockOnDismiss = true
                                showingAddressInput = true
                            }) {
                                Text("Edit")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 15, weight: .medium))
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 34)
                }
                .transition(.move(edge: .bottom))
            }
        }
        .onAppear {
            locationManager.requestLocationPermission()
            savedStore.load()
        }
        .onChange(of: locationManager.userLocation) {
            if let location = locationManager.userLocation {
                region.center = location.coordinate
            }
        }
        .sheet(isPresented: $showingAddressInput, onDismiss: {
            if shouldUnlockOnDismiss { unlockMap() } else { shouldUnlockOnDismiss = true }
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
                },
                isCalculatingTolls: $isCalculatingTolls
            )
        }
        .toastify(using: toastManager)
        .sheet(isPresented: $showSaveSheet) {
            VStack(spacing: 16) {
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                Text("Name this toll")
                    .font(.system(size: 16, weight: .semibold))
                TextField("Toll name", text: $savedTollName)
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                Button(action: {
                    isTollSaved = true
                    let toll = SavedToll(id: UUID(), name: savedTollName.isEmpty ? "Saved Toll" : savedTollName, summary: tollSummaryText, totalA: tollAmountA, totalB: tollAmountB, stops: allStops)
                    savedStore.saveOrUpdate(toll: toll)
                    print("Saved toll created: \(toll.id.uuidString) \(toll.name) A: \(String(format: "%.2f", toll.totalA)) B: \(String(format: "%.2f", toll.totalB))")
                    print("Saved tolls count after save: \(savedStore.items.count)")
                    showSaveSheet = false
                    showSaveSuccess = true
                    toastManager.show(toast: ToastModel(
                        message: "Toll saved successfully!",
                        icon: "checkmark.circle.fill",
                        backgroundColor: .green,
                        duration: 1.5
                    ))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        showSaveSuccess = false
                    }
                }) {
                    Text("Save Toll")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.black)
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                }
                Spacer(minLength: 16)
            }
            .presentationDetents([.height(220)])
        }
        .sheet(isPresented: $showSavedList) {
            NavigationView {
                List {
                    ForEach(savedStore.items) { toll in
                        Button(action: {
                            showSavedList = false
                            tollSummaryText = toll.summary
                            tollAmountA = toll.totalA
                            tollAmountB = toll.totalB
                            isTollSaved = true
                            currentViewingSavedTollId = toll.id
                            stopAddresses = toll.stops.map { $0.address }
                            allStops = toll.stops
                            updateMapAnnotations()
                            frameAllStops()
                            isMapLocked = true
                            didFitOnce = false
                            showTollCard = true
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(toll.name)
                                        .foregroundColor(.black)
                                        .font(.system(size: 16, weight: .semibold))
                                    if currentViewingSavedTollId == toll.id {
                                        Spacer()
                                        Text("Viewing")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.blue)
                                    }
                                }
                                Text(toll.summary)
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                                HStack {
                                    Text("A $\(String(format: "%.2f", toll.totalA))")
                                    Text("B $\(String(format: "%.2f", toll.totalB))")
                                }
                                .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet { savedStore.delete(id: savedStore.items[idx].id) }
                    }
                }
                .navigationTitle("Saved Tolls")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
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
        
        isCalculatingTolls = true
        let tollPrice = calculateTollPrice(for: validStops)
        currentRoute = Route(stops: validStops, tollPrice: tollPrice)
        print("Route created with \(validStops.count) stops")
        print("Toll price - Car: $\(tollPrice.typeA), Truck: $\(tollPrice.typeB)")
        
        Task {
            let result = await tollCalculator.calculateTollsSummary(stops: validStops)
            tollSummaryText = result.summary
            tollAmountA = result.totalA
            tollAmountB = result.totalB
            if let currentId = currentViewingSavedTollId, let idx = savedStore.items.firstIndex(where: { $0.id == currentId }) {
                var updated = savedStore.items[idx]
                updated.summary = tollSummaryText
                updated.totalA = tollAmountA
                updated.totalB = tollAmountB
                updated.stops = validStops
                savedStore.saveOrUpdate(toll: updated)
            }
            isCalculatingTolls = false
            frameAllStops()
            isMapLocked = true
            shouldUnlockOnDismiss = false
            didFitOnce = false
            showingAddressInput = false
            showTollCard = true
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
        routeEndpoints = []
        
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
                    self.routeEndpoints.append((start: startStop.coordinate, end: endStop.coordinate))
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
    @Binding var didFitOnce: Bool
    
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
            if !rect.isNull && !didFitOnce {
                let expanded = rect.insetBy(dx: -rect.size.width * 0.1, dy: -rect.size.height * 0.1)
                let insets = UIEdgeInsets(top: 120, left: 120, bottom: 240, right: 120)
                mapView.setVisibleMapRect(expanded, edgePadding: insets, animated: true)
                didFitOnce = true
            }
        } else {
            if !mkAnnotations.isEmpty && polylines.isEmpty {
                var rect = MKMapRect.null
                for annotation in mapView.annotations where !(annotation is MKUserLocation) {
                    let point = MKMapPoint(annotation.coordinate)
                    let smallRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
                    rect = rect.union(smallRect)
                }
                if !rect.isNull && !didFitOnce {
                    let expanded = rect.insetBy(dx: -rect.size.width * 0.1, dy: -rect.size.height * 0.1)
                    let insets = UIEdgeInsets(top: 120, left: 120, bottom: 240, right: 120)
                    mapView.setVisibleMapRect(expanded, edgePadding: insets, animated: true)
                    didFitOnce = true
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
                renderer.lineWidth = 4
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

/* moved to Models.swift */
 


 

 

struct ShimmeringRoutesOverlay: View {
    @Binding var region: MKCoordinateRegion
    let polylines: [MKPolyline]
    let endpoints: [(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)]
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(polylines.enumerated()), id: \.offset) { idx, poly in
                    let coords = orderedPolylineCoords(poly, index: idx)
                    if coords.count > 1 {
                        Path { path in
                            let first = mapPoint(for: coords[0], in: geo.size)
                            path.move(to: first)
                            for coord in coords.dropFirst() {
                                path.addLine(to: mapPoint(for: coord, in: geo.size))
                            }
                        }
                        .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .foregroundStyle(.black.opacity(0.5))
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
    
    private func orderedPolylineCoords(_ polyline: MKPolyline, index: Int) -> [CLLocationCoordinate2D] {
        var coords = polyPoints(polyline)
        guard coords.count > 1 else { return coords }
        if index < endpoints.count {
            let desiredStart = endpoints[index].start
            if let startIdx = coords.enumerated().min(by: { lhs, rhs in
                distanceSquared(lhs.element, desiredStart) < distanceSquared(rhs.element, desiredStart)
            })?.offset, startIdx != 0 {
                coords = Array(coords[startIdx...] + coords[..<startIdx])
            }
        }
        return coords
    }
    
    private func mapPoint(for coordinate: CLLocationCoordinate2D, in size: CGSize) -> CGPoint {
        let rect = regionMapRect(region)
        let point = MKMapPoint(coordinate)
        let x = ((point.x - rect.origin.x) / rect.size.width) * size.width
        let y = ((point.y - rect.origin.y) / rect.size.height) * size.height
        return CGPoint(x: x, y: y)
    }

    private func lastLongitudeLessThan(_ first: CLLocationCoordinate2D, _ last: CLLocationCoordinate2D) -> Bool {
        return last.longitude < first.longitude
    }

    private func distanceSquared(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dx = a.latitude - b.latitude
        let dy = a.longitude - b.longitude
        return dx*dx + dy*dy
    }

    private func regionMapRect(_ region: MKCoordinateRegion) -> MKMapRect {
        let center = region.center
        let span = region.span
        let north = center.latitude + span.latitudeDelta / 2
        let south = center.latitude - span.latitudeDelta / 2
        let west = center.longitude - span.longitudeDelta / 2
        let east = center.longitude + span.longitudeDelta / 2
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
        let origin = MKMapPoint(x: min(nw.x, se.x), y: min(nw.y, se.y))
        let size = MKMapSize(width: abs(se.x - nw.x), height: abs(se.y - nw.y))
        return MKMapRect(origin: origin, size: size)
    }
}
struct AddressInputSheet_OLD: View {
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
    @Binding var isCalculatingTolls: Bool
    
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
                    HStack(spacing: 10) {
                        if isCalculatingTolls {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "function")
                                .font(.system(size: 16, weight: .medium))
                        }
                        Text(isCalculatingTolls ? "Calculating..." : "Calculate Tolls")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(allFilled ? Color.black : Color.gray)
                    .cornerRadius(8)
                }
                .disabled(!allFilled || isCalculatingTolls)
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
        
        let nswCenter = CLLocationCoordinate2D(latitude: -32.0, longitude: 147.0)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(
            center: nswCenter,
            span: MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 12.0)
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
                let filtered = response.mapItems.filter { item in
                    let area = (item.placemark.administrativeArea ?? "").uppercased()
                    return area.contains("NSW") || area.contains("NEW SOUTH WALES")
                }
                self.searchResults = filtered
                print("Search for '\(query)' returned \(filtered.count) NSW results")
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