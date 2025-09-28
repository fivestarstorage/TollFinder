import SwiftUI
import MapKit
import CoreLocation
import Combine
import CoreData

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

struct SavedToll: Identifiable, Codable {
    let id: UUID
    var name: String
    var summary: String
    var totalA: Double
    var totalB: Double
    var stops: [RouteStop]
}

@MainActor
final class SavedTollStore: ObservableObject {
    static let shared = SavedTollStore()
    @Published var items: [SavedToll] = []
    private var context: NSManagedObjectContext { PersistenceController.shared.container.viewContext }
    func load() {
        guard NSEntityDescription.entity(forEntityName: "SavedTollEntity", in: context) != nil,
              NSEntityDescription.entity(forEntityName: "SavedStopEntity", in: context) != nil else {
            loadFromDefaults()
            return
        }
        let req = NSFetchRequest<NSManagedObject>(entityName: "SavedTollEntity")
        do {
            let tollEntities = try context.fetch(req)
            items = tollEntities.compactMap { toll in
                guard let id = toll.value(forKey: "id") as? UUID,
                      let name = toll.value(forKey: "name") as? String,
                      let summary = toll.value(forKey: "summary") as? String else { return nil }
                let totalA = toll.value(forKey: "totalA") as? Double ?? 0
                let totalB = toll.value(forKey: "totalB") as? Double ?? 0
                let relation = toll.value(forKey: "stops") as? NSSet
                let stopsArray = (relation?.allObjects as? [NSManagedObject] ?? []).sorted { a, b in
                    let oa = a.value(forKey: "orderIndex") as? Int16 ?? 0
                    let ob = b.value(forKey: "orderIndex") as? Int16 ?? 0
                    return oa < ob
                }.map { s in
                    let lat = s.value(forKey: "latitude") as? Double ?? 0
                    let lon = s.value(forKey: "longitude") as? Double ?? 0
                    let addr = s.value(forKey: "address") as? String ?? ""
                    let ord = Int(s.value(forKey: "orderIndex") as? Int16 ?? 0)
                    return RouteStop(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), address: addr, order: ord)
                }
                return SavedToll(id: id, name: name, summary: summary, totalA: totalA, totalB: totalB, stops: stopsArray)
            }
        } catch {}
    }
    func saveOrUpdate(toll: SavedToll) {
        guard NSEntityDescription.entity(forEntityName: "SavedTollEntity", in: context) != nil,
              NSEntityDescription.entity(forEntityName: "SavedStopEntity", in: context) != nil else {
            if let idx = items.firstIndex(where: { $0.id == toll.id }) { items[idx] = toll } else { items.append(toll) }
            saveToDefaults()
            return
        }
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "SavedTollEntity")
        fetch.predicate = NSPredicate(format: "id == %@", toll.id as CVarArg)
        let tollEntity: NSManagedObject
        if let existing = ((try? context.fetch(fetch))?.first) {
            tollEntity = existing
        } else {
            let entity = NSEntityDescription.entity(forEntityName: "SavedTollEntity", in: context)!
            tollEntity = NSManagedObject(entity: entity, insertInto: context)
            tollEntity.setValue(toll.id, forKey: "id")
        }
        tollEntity.setValue(toll.name, forKey: "name")
        tollEntity.setValue(toll.summary, forKey: "summary")
        tollEntity.setValue(toll.totalA, forKey: "totalA")
        tollEntity.setValue(toll.totalB, forKey: "totalB")
        let currentStops = tollEntity.mutableSetValue(forKey: "stops")
        currentStops.removeAllObjects()
        for s in toll.stops {
            let stopEntity = NSEntityDescription.insertNewObject(forEntityName: "SavedStopEntity", into: context)
            stopEntity.setValue(Double(s.latitude), forKey: "latitude")
            stopEntity.setValue(Double(s.longitude), forKey: "longitude")
            stopEntity.setValue(s.address, forKey: "address")
            stopEntity.setValue(Int16(s.order), forKey: "orderIndex")
            currentStops.add(stopEntity)
        }
        tollEntity.setValue(currentStops, forKey: "stops")
        try? context.save()
        if let idx = items.firstIndex(where: { $0.id == toll.id }) { items[idx] = toll } else { items.append(toll) }
        saveToDefaults()
    }
    func delete(id: UUID) {
        guard NSEntityDescription.entity(forEntityName: "SavedTollEntity", in: context) != nil else {
            items.removeAll { $0.id == id }
            saveToDefaults()
            return
        }
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "SavedTollEntity")
        fetch.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let entity = ((try? context.fetch(fetch))?.first) {
            context.delete(entity)
            try? context.save()
        }
        items.removeAll { $0.id == id }
        saveToDefaults()
    }
    private func saveToDefaults() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "saved_tolls_v1")
        }
    }
    private func loadFromDefaults() {
        if let data = UserDefaults.standard.data(forKey: "saved_tolls_v1"), let decoded = try? JSONDecoder().decode([SavedToll].self, from: data) {
            items = decoded
        }
    }
}


