import Foundation
import Combine
import CoreLocation
import MapKit

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

    func calculateTollsSummary(stops: [RouteStop]) async -> (summary: String, totalA: Double, totalB: Double) {
        guard stops.count >= 2 else { return ("", 0, 0) }
        var totalA: Double = 0
        var totalB: Double = 0
        var lastSummary: String = ""
        for i in 0..<(stops.count - 1) {
            let a = stops[i]
            let b = stops[i + 1]
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
                totalA += resultA.amount
                totalB += resultB.amount
                lastSummary = resultA.summary
            } catch {
                continue
            }
        }
        return (lastSummary, totalA, totalB)
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


