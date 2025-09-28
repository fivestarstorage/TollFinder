import SwiftUI
import MapKit
import CoreLocation

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

struct StopAnnotation: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    let color: Color
}

struct SavedToll: Identifiable {
    let id: UUID
    var name: String
    var summary: String
    var totalA: Double
    var totalB: Double
    var stops: [RouteStop]
}


