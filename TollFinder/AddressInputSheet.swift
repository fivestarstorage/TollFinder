import SwiftUI
import MapKit

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
    @Binding var isCalculatingTolls: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var searchTimer: Timer?
    @FocusState private var focusedField: MapView.ActiveField?
    private func getStopPlaceholder(for index: Int) -> String { "Stop \(index + 1)" }
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    ForEach(0..<stopAddresses.count, id: \.self) { index in
                        stopTextField(for: index)
                    }
                    .onMove(perform: moveStops)
                    Button(action: { onUseCurrentLocation() }) {
                        HStack {
                            Image(systemName: "location.fill").font(.system(size: 14, weight: .medium))
                            Text("Use Current Location").font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                    if !searchResults.isEmpty {
                        ForEach(Array(searchResults.enumerated()), id: \.offset) { _, mapItem in
                            Button(action: { onLocationSelected(mapItem) }) {
                                HStack {
                                    Image(systemName: "mappin.circle.fill").foregroundColor(.gray).font(.system(size: 20))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mapItem.name ?? "Unknown Location").font(.system(size: 16)).foregroundColor(.black).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(getAddress(mapItem)).font(.system(size: 14)).foregroundColor(.gray).frame(maxWidth: .infinity, alignment: .leading)
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
                let allValid = (0..<stopAddresses.count).allSatisfy { idx in
                    let txt = stopAddresses[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !txt.isEmpty, idx < allStops.count else { return false }
                    let s = allStops[idx]
                    return !s.address.isEmpty && s.latitude != 0 && s.longitude != 0
                }
                Button(action: { if allValid { onFindTolls() } }) {
                    HStack(spacing: 10) {
                        if isCalculatingTolls { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)) } else { Image(systemName: "function").font(.system(size: 16, weight: .medium)) }
                        Text(isCalculatingTolls ? "Calculating..." : "Calculate Tolls").font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(allValid ? Color.black : Color.gray)
                    .cornerRadius(8)
                }
                .disabled(!allValid || isCalculatingTolls)
                .padding(.horizontal, 16)
                .padding(.bottom, 34)
            }
            .navigationTitle("Plan your trip").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } } }
            .onChange(of: activeField) {
                focusedField = activeField
                switch activeField { case .stop(let index): if index < stopAddresses.count && !stopAddresses[index].isEmpty { performSearch(query: stopAddresses[index]) }; case .none: break }
            }
        }
    }
    private var addressInputSection: some View { List { ForEach(0..<stopAddresses.count, id: \.self) { index in stopTextField(for: index).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)) } .onMove(perform: moveStops) }.environment(\.editMode, .constant(.active)).listStyle(.plain) }
    private func stopTextField(for index: Int) -> some View { HStack(spacing: 8) { TextField(getStopPlaceholder(for: index), text: $stopAddresses[index]).font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 12).background(Color.gray.opacity(0.1)).cornerRadius(8).focused($focusedField, equals: .stop(index)).onTapGesture { activeField = .stop(index) }.onChange(of: stopAddresses[index]) { activeField = .stop(index); debounceSearch(query: stopAddresses[index]) } ; if stopAddresses.count > 2 { if stopAddresses.count == 5 || index < stopAddresses.count - 1 { Button(action: { removeStop(at: index) }) { Image(systemName: "minus.circle.fill").font(.system(size: 20)).foregroundColor(.gray) } } } ; if index == stopAddresses.count - 1 && stopAddresses.count < 5 { Button(action: { onAddStop() }) { Image(systemName: "plus").font(.system(size: 16, weight: .medium)).foregroundColor(.black).frame(width: 32, height: 32).background(Color.gray.opacity(0.1)).clipShape(Circle()) } } } }
    private func removeStop(at index: Int) { onRemoveStop(index) }
    private var addStopButton: some View { Button(action: { onAddStop() }) { Image(systemName: "plus").font(.system(size: 16, weight: .medium)).foregroundColor(.black).frame(width: 32, height: 32).background(Color.gray.opacity(0.1)).clipShape(Circle()) }.padding(.trailing, 16) }
    private var useCurrentLocationButton: some View { Button(action: { onUseCurrentLocation() }) { HStack { Image(systemName: "location.fill").font(.system(size: 14, weight: .medium)); Text("Use Current Location").font(.system(size: 14, weight: .medium)) }.foregroundColor(.blue).frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.blue.opacity(0.1)).cornerRadius(8) }.padding(.horizontal, 16).padding(.vertical, 8) }
    private func debounceSearch(query: String) { searchTimer?.invalidate(); searchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in performSearch(query: query) } }
    private func performSearch(query: String) { guard query.count > 2 else { searchResults = []; return }; let nswCenter = CLLocationCoordinate2D(latitude: -32.0, longitude: 147.0); let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query; request.resultTypes = [.address, .pointOfInterest]; request.region = MKCoordinateRegion(center: nswCenter, span: MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 12.0)); let search = MKLocalSearch(request: request); search.start { response, error in if error != nil { DispatchQueue.main.async { self.searchResults = [] }; return }; guard let response = response else { DispatchQueue.main.async { self.searchResults = [] }; return }; DispatchQueue.main.async { let filtered = response.mapItems.filter { item in let area = (item.placemark.administrativeArea ?? "").uppercased(); return area.contains("NSW") || area.contains("NEW SOUTH WALES") }; self.searchResults = filtered } } }
    private func getAddress(_ mapItem: MKMapItem) -> String { let placemark = mapItem.placemark; var parts: [String] = []; if let street = placemark.thoroughfare { parts.append(street) }; if let city = placemark.locality { parts.append(city) }; if let state = placemark.administrativeArea { parts.append(state) }; return parts.isEmpty ? "No address" : parts.joined(separator: ", ") }
    private func moveStops(from source: IndexSet, to destination: Int) { stopAddresses.move(fromOffsets: source, toOffset: destination); allStops.move(fromOffsets: source, toOffset: destination); for i in 0..<allStops.count { allStops[i] = RouteStop(coordinate: allStops[i].coordinate, address: allStops[i].address, order: i) }; onStopsReordered() }
}


