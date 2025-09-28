//
//  TollFinderTests.swift
//  TollFinderTests
//
//  Created by Riley Martin on 24/9/2025.
//

import Testing
import CoreLocation
import CoreData
import SwiftUI
@testable import TollFinder

struct TollFinderTests {

    @Test func testRouteStopInitialization() async throws {
        let coordinate = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        let stop = RouteStop(coordinate: coordinate, address: "Sydney Opera House", order: 0)
        
        #expect(stop.latitude == -33.8688)
        #expect(stop.longitude == 151.2093)
        #expect(stop.address == "Sydney Opera House")
        #expect(stop.order == 0)
        #expect(stop.coordinate.latitude == coordinate.latitude)
        #expect(stop.coordinate.longitude == coordinate.longitude)
    }

    @Test func testTollPriceInitialization() async throws {
        let tollPrice = TollPrice(typeA: 5.50, typeB: 8.25)
        
        #expect(tollPrice.typeA == 5.50)
        #expect(tollPrice.typeB == 8.25)
    }

    @Test func testCarTypeDisplayNames() async throws {
        #expect(CarType.typeA.displayName == "Car")
        #expect(CarType.typeB.displayName == "Truck/Van")
        #expect(CarType.typeA.rawValue == "Car")
        #expect(CarType.typeB.rawValue == "Truck/Van")
    }

    @Test func testRouteInitialization() async throws {
        let stop1 = RouteStop(coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093), address: "Sydney", order: 0)
        let stop2 = RouteStop(coordinate: CLLocationCoordinate2D(latitude: -33.8675, longitude: 151.2070), address: "Circular Quay", order: 1)
        let stops = [stop1, stop2]
        let tollPrice = TollPrice(typeA: 5.50, typeB: 8.25)
        
        let route = Route(stops: stops, tollPrice: tollPrice, totalDistance: 1500.0, estimatedDuration: 300.0)
        
        #expect(route.stops.count == 2)
        #expect(route.tollPrice.typeA == 5.50)
        #expect(route.tollPrice.typeB == 8.25)
        #expect(route.totalDistance == 1500.0)
        #expect(route.estimatedDuration == 300.0)
        #expect(route.orderedStops.count == 2)
        #expect(route.orderedStops[0].order == 0)
        #expect(route.orderedStops[1].order == 1)
        #expect(route.startLocation?.address == "Sydney")
        #expect(route.endLocation?.address == "Circular Quay")
    }

    @Test func testRouteTollPriceCalculation() async throws {
        let stops = [RouteStop(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), address: "Start", order: 0)]
        let tollPrice = TollPrice(typeA: 10.0, typeB: 15.0)
        let route = Route(stops: stops, tollPrice: tollPrice)
        
        #expect(route.getTollPrice(for: .typeA) == 10.0)
        #expect(route.getTollPrice(for: .typeB) == 15.0)
    }

    @Test func testStopAnnotationInitialization() async throws {
        let coordinate = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        let annotation = StopAnnotation(id: UUID(), coordinate: coordinate, title: "Test Stop", subtitle: "Test Subtitle", color: .red)
        
        #expect(annotation.coordinate.latitude == -33.8688)
        #expect(annotation.coordinate.longitude == 151.2093)
        #expect(annotation.title == "Test Stop")
        #expect(annotation.subtitle == "Test Subtitle")
        #expect(annotation.color == .red)
    }

    @Test func testSavedTollInitialization() async throws {
        let stop1 = RouteStop(coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093), address: "Sydney", order: 0)
        let stop2 = RouteStop(coordinate: CLLocationCoordinate2D(latitude: -33.8675, longitude: 151.2070), address: "Circular Quay", order: 1)
        let stops = [stop1, stop2]
        
        let savedToll = SavedToll(id: UUID(), name: "Test Route", summary: "Sydney to Circular Quay", totalA: 5.50, totalB: 8.25, stops: stops)
        
        #expect(savedToll.name == "Test Route")
        #expect(savedToll.summary == "Sydney to Circular Quay")
        #expect(savedToll.totalA == 5.50)
        #expect(savedToll.totalB == 8.25)
        #expect(savedToll.stops.count == 2)
        #expect(savedToll.stops[0].address == "Sydney")
        #expect(savedToll.stops[1].address == "Circular Quay")
    }

    @MainActor
    @Test func testSavedTollStoreInitialization() async throws {
        let store = SavedTollStore()
        #expect(store.items.isEmpty)
    }

    @MainActor
    @Test func testSavedTollStoreSaveAndRetrieve() async throws {
        let store = SavedTollStore()
        let stops = [RouteStop(coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093), address: "Sydney", order: 0)]
        let toll = SavedToll(id: UUID(), name: "Test Toll", summary: "Test Summary", totalA: 10.0, totalB: 15.0, stops: stops)
        
        store.saveOrUpdate(toll: toll)
        
        #expect(store.items.count == 1)
        #expect(store.items.first?.name == "Test Toll")
        #expect(store.items.first?.summary == "Test Summary")
        #expect(store.items.first?.totalA == 10.0)
        #expect(store.items.first?.totalB == 15.0)
    }

    @MainActor
    @Test func testSavedTollStoreUpdate() async throws {
        let store = SavedTollStore()
        let stops = [RouteStop(coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093), address: "Sydney", order: 0)]
        let tollId = UUID()
        let originalToll = SavedToll(id: tollId, name: "Original", summary: "Original Summary", totalA: 5.0, totalB: 7.5, stops: stops)
        
        store.saveOrUpdate(toll: originalToll)
        #expect(store.items.count == 1)
        
        let updatedToll = SavedToll(id: tollId, name: "Updated", summary: "Updated Summary", totalA: 10.0, totalB: 15.0, stops: stops)
        store.saveOrUpdate(toll: updatedToll)
        
        #expect(store.items.count == 1)
        #expect(store.items.first?.name == "Updated")
        #expect(store.items.first?.summary == "Updated Summary")
        #expect(store.items.first?.totalA == 10.0)
        #expect(store.items.first?.totalB == 15.0)
    }

    @MainActor
    @Test func testSavedTollStoreDelete() async throws {
        let store = SavedTollStore()
        let stops = [RouteStop(coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093), address: "Sydney", order: 0)]
        let toll = SavedToll(id: UUID(), name: "Test Toll", summary: "Test Summary", totalA: 10.0, totalB: 15.0, stops: stops)
        
        store.saveOrUpdate(toll: toll)
        #expect(store.items.count == 1)
        
        store.delete(id: toll.id)
        #expect(store.items.isEmpty)
    }

    @MainActor
    @Test func testSavedTollStoreMultipleTolls() async throws {
        let store = SavedTollStore()
        let stops = [RouteStop(coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093), address: "Sydney", order: 0)]
        
        let toll1 = SavedToll(id: UUID(), name: "Toll 1", summary: "Summary 1", totalA: 5.0, totalB: 7.5, stops: stops)
        let toll2 = SavedToll(id: UUID(), name: "Toll 2", summary: "Summary 2", totalA: 10.0, totalB: 15.0, stops: stops)
        let toll3 = SavedToll(id: UUID(), name: "Toll 3", summary: "Summary 3", totalA: 15.0, totalB: 22.5, stops: stops)
        
        store.saveOrUpdate(toll: toll1)
        store.saveOrUpdate(toll: toll2)
        store.saveOrUpdate(toll: toll3)
        
        #expect(store.items.count == 3)
        
        store.delete(id: toll2.id)
        #expect(store.items.count == 2)
        #expect(!store.items.contains { $0.id == toll2.id })
        #expect(store.items.contains { $0.id == toll1.id })
        #expect(store.items.contains { $0.id == toll3.id })
    }

    @Test func testRouteOrderedStops() async throws {
        let stop1 = RouteStop(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), address: "Third", order: 2)
        let stop2 = RouteStop(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), address: "First", order: 0)
        let stop3 = RouteStop(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), address: "Second", order: 1)
        let stops = [stop1, stop2, stop3]
        let tollPrice = TollPrice(typeA: 5.0, typeB: 7.5)
        
        let route = Route(stops: stops, tollPrice: tollPrice)
        let orderedStops = route.orderedStops
        
        #expect(orderedStops.count == 3)
        #expect(orderedStops[0].address == "First")
        #expect(orderedStops[1].address == "Second")
        #expect(orderedStops[2].address == "Third")
        #expect(orderedStops[0].order == 0)
        #expect(orderedStops[1].order == 1)
        #expect(orderedStops[2].order == 2)
    }

    @Test func testRouteStartAndEndLocations() async throws {
        let stop1 = RouteStop(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), address: "Start", order: 0)
        let stop2 = RouteStop(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), address: "Middle", order: 1)
        let stop3 = RouteStop(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), address: "End", order: 2)
        let stops = [stop2, stop3, stop1]
        let tollPrice = TollPrice(typeA: 5.0, typeB: 7.5)
        
        let route = Route(stops: stops, tollPrice: tollPrice)
        
        #expect(route.startLocation?.address == "Start")
        #expect(route.endLocation?.address == "End")
        #expect(route.startLocation?.order == 0)
        #expect(route.endLocation?.order == 2)
    }

    @Test func testEmptyRouteStartAndEndLocations() async throws {
        let stops: [RouteStop] = []
        let tollPrice = TollPrice(typeA: 5.0, typeB: 7.5)
        let route = Route(stops: stops, tollPrice: tollPrice)
        
        #expect(route.startLocation == nil)
        #expect(route.endLocation == nil)
    }

    @Test func testSingleStopRouteStartAndEndLocations() async throws {
        let stop = RouteStop(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), address: "Only Stop", order: 0)
        let stops = [stop]
        let tollPrice = TollPrice(typeA: 5.0, typeB: 7.5)
        let route = Route(stops: stops, tollPrice: tollPrice)
        
        #expect(route.startLocation?.address == "Only Stop")
        #expect(route.endLocation?.address == "Only Stop")
        #expect(route.startLocation?.id == route.endLocation?.id)
    }

}
