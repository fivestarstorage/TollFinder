import SwiftUI
import MapKit
import CoreLocation
import Combine
import ToastifySwift

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
    
    enum ActiveField: Equatable {
        case stop(Int)
    }
    
    var body: some View {
        ZStack {
        Map(coordinateRegion: $region, interactionModes: isMapLocked ? [] : .all, showsUserLocation: true, annotationItems: mapAnnotations) { annotation in
            MapAnnotation(coordinate: annotation.coordinate) {
                VStack {
                    Text(annotation.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(annotation.color)
                        .cornerRadius(8)
                        .shadow(radius: 2)
                    
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(annotation.color)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(radius: 2)
                }
            }
        }
        .ignoresSafeArea()
            
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
                            
                            if index + 1 < self.stopAddresses.count {
                                self.activeField = .stop(index + 1)
                            }
                        }
                        
                    case .none:
                        break
                    }
                    
                    self.updateMapAnnotations()
                    self.frameAllStops()
                    
                    self.searchResults = []
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
                color: .blue
            )
        }
        print("updateMapAnnotations: Created \(mapAnnotations.count) annotations")
    }
    
    private func frameAllStops() {
        // Filter out stops with invalid coordinates (0,0 or empty addresses without coordinates)
        let validStops = allStops.filter { stop in
            let isValid = stop.coordinate.latitude != 0 && stop.coordinate.longitude != 0 && !stop.address.isEmpty
            if !isValid {
                print("Skipping invalid stop: '\(stop.address)' at \(stop.coordinate.latitude), \(stop.coordinate.longitude)")
            }
            return isValid
        }
        
        guard validStops.count > 1 else { 
            print("frameAllStops: Not enough valid stops (\(validStops.count) out of \(allStops.count))")
            return 
        }
        
        print("frameAllStops: Framing \(validStops.count) valid stops out of \(allStops.count) total")
        for (index, stop) in validStops.enumerated() {
            print("Valid Stop \(index + 1): '\(stop.address)' at \(stop.coordinate.latitude), \(stop.coordinate.longitude)")
        }
        
        let coordinates = validStops.map { $0.coordinate }
        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat, 0.01) * 1.5,
            longitudeDelta: max(maxLon - minLon, 0.01) * 1.5
        )
        
        print("frameAllStops: Bounds - minLat: \(minLat), maxLat: \(maxLat), minLon: \(minLon), maxLon: \(maxLon)")
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
        
        // Lock the map after framing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            self.isMapLocked = true
            print("Map locked - interaction disabled")
        }
    }
    
    private func unlockMap() {
        isMapLocked = false
        print("Map unlocked - interaction enabled")
    }
}

struct StopAnnotation: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    let color: Color
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
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchTimer: Timer?
    
    private func getStopPlaceholder(for index: Int) -> String {
        return "Stop \(index + 1)"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                addressInputSection
                
                useCurrentLocationButton
                
                if !searchResults.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text("\(searchResults.count) results found")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            Spacer()
                        }
                        .background(Color.blue.opacity(0.1))
                        
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(searchResults.enumerated()), id: \.offset) { index, mapItem in
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
                                                
                                                HStack {
                                                    Text(getAddress(mapItem))
                                                        .font(.system(size: 14))
                                                        .foregroundColor(.gray)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                    
                                                    if let userLocation = userLocation {
                                                        Text(getDistanceText(mapItem, from: userLocation))
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.blue)
                                                    }
                                                }
                                            }
                                            
                                            Spacer()
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    if index < searchResults.count - 1 {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(height: 1)
                                            .padding(.leading, 52)
                                    }
                                }
                            }
                        }
                    }
                }
                
                
                Spacer()
                
                Button(action: {
                    onFindTolls()
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
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(0..<stopAddresses.count, id: \.self) { index in
                        Circle()
                            .fill(Color.black)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 12)
                
                VStack(spacing: 12) {
                    ForEach(0..<stopAddresses.count, id: \.self) { index in
                        stopTextField(for: index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                
                Spacer()
                
                addStopButton
            }
        }
        .background(Color.gray.opacity(0.05))
    }
    
    private func stopTextField(for index: Int) -> some View {
        HStack {
            TextField(getStopPlaceholder(for: index), text: $stopAddresses[index])
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(activeField == .stop(index) ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                .cornerRadius(8)
                .onTapGesture {
                    activeField = .stop(index)
                }
                .onChange(of: stopAddresses[index]) {
                    activeField = .stop(index)
                    print("Text changed for stop \(index + 1): '\(stopAddresses[index])'")
                    debounceSearch(query: stopAddresses[index])
                }
            
            if stopAddresses.count > 2 {
                Button(action: {
                    removeStop(at: index)
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
                .padding(.trailing, 8)
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
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
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
                let sortedResults = self.sortResultsByDistance(response.mapItems, userLocation: self.userLocation)
                self.searchResults = sortedResults
                print("Search for '\(query)' returned \(response.mapItems.count) results near your location")
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