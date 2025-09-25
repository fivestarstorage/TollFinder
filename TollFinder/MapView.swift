import SwiftUI
import MapKit
import CoreLocation
import Combine

struct MapView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var fromAddress = ""
    @State private var toAddress = ""
    @State private var showingAddressInput = false
    @State private var activeField: ActiveField?
    @State private var searchResults: [MKMapItem] = []
    
    enum ActiveField {
        case from, to
    }
    
    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, showsUserLocation: true)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 12, height: 12)
                                
                                Text(fromAddress.isEmpty ? "From" : fromAddress)
                                    .font(.system(size: 16))
                                    .foregroundColor(fromAddress.isEmpty ? .gray : .black)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activeField = .from
                                showingAddressInput = true
                            }
                            
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                                .padding(.leading, 20)
                            
                            HStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)
                                
                                Text(toAddress.isEmpty ? "To" : toAddress)
                                    .font(.system(size: 16))
                                    .foregroundColor(toAddress.isEmpty ? .gray : .black)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activeField = .to
                                showingAddressInput = true
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        
                        Spacer()
                        
                        Button(action: {
                            
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
                    
                    Button(action: {
                        searchForTolls()
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
                    .padding(.bottom, 16)
                }
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -2)
                .padding(.horizontal, 16)
                .padding(.bottom, 34)
            }
            
            VStack {
                HStack {
                    Spacer()
                    
                    VStack(spacing: 12) {
                        Button(action: {
                            centerOnUserLocation()
                        }) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                                .background(Color.white)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                        
                        Button(action: {
                            
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                                .background(Color.white)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                    }
                }
                .padding(.trailing, 16)
                .padding(.top, 60)
                
                Spacer()
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
        .sheet(isPresented: $showingAddressInput) {
            AddressInputSheet(
                fromAddress: $fromAddress,
                toAddress: $toAddress,
                activeField: $activeField,
                searchResults: $searchResults,
                userLocation: locationManager.userLocation,
                onLocationSelected: selectLocation
            )
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
        
    }
    
    private func selectLocation(_ mapItem: MKMapItem) {
        let locationName = mapItem.name ?? "Unknown Location"
        
        if activeField == .from {
            fromAddress = locationName
            // Move to "To" field automatically
            activeField = .to
        } else if activeField == .to {
            toAddress = locationName
            // Close sheet after "To" is filled
            showingAddressInput = false
        }
        
        searchResults = []
        
        withAnimation(.easeInOut(duration: 0.5)) {
            region.center = mapItem.placemark.coordinate
        }
    }
}

struct AddressInputSheet: View {
    @Binding var fromAddress: String
    @Binding var toAddress: String
    @Binding var activeField: MapView.ActiveField?
    @Binding var searchResults: [MKMapItem]
    let userLocation: CLLocation?
    let onLocationSelected: (MKMapItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchTimer: Timer?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 12, height: 12)
                                
                                TextField("From", text: $fromAddress)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(.system(size: 16))
                                    .onTapGesture {
                                        activeField = .from
                                        performSearch(query: fromAddress)
                                    }
                                    .onChange(of: fromAddress) {
                                        activeField = .from
                                        debounceSearch(query: fromAddress)
                                    }
                            }
                            
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                                .padding(.leading, 20)
                            
                            HStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)
                                
                                TextField("To", text: $toAddress)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(.system(size: 16))
                                    .onTapGesture {
                                        activeField = .to
                                        performSearch(query: toAddress)
                                    }
                                    .onChange(of: toAddress) {
                                        activeField = .to
                                        debounceSearch(query: toAddress)
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        
                        Spacer()
                    }
                }
                .background(Color.gray.opacity(0.05))
                
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
                // When activeField changes to "To", automatically search if there's existing text
                if activeField == .to && !toAddress.isEmpty {
                    performSearch(query: toAddress)
                } else if activeField == .from && !fromAddress.isEmpty {
                    performSearch(query: fromAddress)
                }
            }
        }
    }
    
    private func debounceSearch(query: String) {
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            performSearch(query: query)
        }
    }
    
    private func performSearch(query: String) {
        guard query.count > 2 else {
            searchResults = []
            return
        }
        
        // Use user's location as search center, fallback to Sydney
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
                // Sort results by distance from user location
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