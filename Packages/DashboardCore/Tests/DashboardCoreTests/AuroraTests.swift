import XCTest
@testable import DashboardCore

/// The Aurora layout's colour from the air and motion from the wind.
final class AuroraTests: XCTestCase {
    /// The angle between two hues, the short way round.
    private func apart(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    func testGoodAirIsGreenWithVioletTops() {
        let curtain = Aurora.curtain(aqi: 20)
        XCTAssertEqual(curtain.edge, 148, accuracy: 4)
        XCTAssertEqual(curtain.fringe, 285)
    }

    func testNoReadingIsGoodAir() {
        XCTAssertEqual(Aurora.curtain(aqi: nil), Aurora.curtain(aqi: 25))
    }

    func testWorseAirWarmsTheCurtain() {
        XCTAssertEqual(Aurora.curtain(aqi: 100).edge, 52, accuracy: 0.01)
        XCTAssertEqual(Aurora.curtain(aqi: 150).edge, 28, accuracy: 0.01)
        XCTAssertEqual(Aurora.curtain(aqi: 200).edge, 350, accuracy: 0.01)
        XCTAssertEqual(Aurora.curtain(aqi: 500).edge, 320, accuracy: 0.01)
        XCTAssertEqual(apart(Aurora.curtain(aqi: 100).fringe, 22), 0, accuracy: 0.01)
    }

    func testTheColourNeverJumps() {
        for aqi in 0..<320 {
            let a = Aurora.curtain(aqi: aqi), b = Aurora.curtain(aqi: aqi + 1)
            XCTAssertLessThan(apart(a.edge, b.edge), 4, "edge at \(aqi)")
            XCTAssertLessThan(apart(a.fringe, b.fringe), 8, "fringe at \(aqi)")
            XCTAssert((0..<360).contains(a.edge) && (0..<360).contains(a.fringe))
        }
    }

    func testTheWindStirsTheCurtains() {
        XCTAssertEqual(Aurora.unrest(windSpeed: 0, isMetric: false), 0)
        XCTAssertEqual(Aurora.unrest(windSpeed: 25, isMetric: false), 1)
        XCTAssertEqual(Aurora.unrest(windSpeed: 11.176, isMetric: true), 1, accuracy: 0.001)
        XCTAssertEqual(Aurora.unrest(windSpeed: 80, isMetric: false), 1.6)
        XCTAssertEqual(Aurora.unrest(windSpeed: nil, isMetric: false), 0.3)
    }
}
