import XCTest
@testable import Synapse

final class VisionPVTEngineTests: XCTestCase {
    func testPeripheralQueueNeverIncludesCenter() {
        let queue = VisionPVTLayout.makeBalancedPeripheralQueue(count: 24)
        XCTAssertEqual(queue.count, 24)
        XCTAssertFalse(queue.contains(VisionPVTLayout.centerCell))
        for cell in queue {
            XCTAssertTrue(VisionPVTLayout.peripheralCells.contains(cell))
        }
    }

    func testPeripheralQueueIsBalancedAcrossEightCells() {
        let queue = VisionPVTLayout.makeBalancedPeripheralQueue(count: 16)
        var counts: [Int: Int] = [:]
        for cell in queue {
            counts[cell, default: 0] += 1
        }
        XCTAssertEqual(counts.keys.count, 8)
        for cell in VisionPVTLayout.peripheralCells {
            XCTAssertEqual(counts[cell], 2)
        }
    }

    func testCellCenterUVMatchesRowMajorGrid() {
        XCTAssertEqual(VisionPVTLayout.cellCenterUV(4), SIMD2<Float>(0.5, 0.5))
        XCTAssertEqual(VisionPVTLayout.cellCenterUV(0).x, 1.0 / 6, accuracy: 1e-5)
        XCTAssertEqual(VisionPVTLayout.cellCenterUV(0).y, 1.0 / 6, accuracy: 1e-5)
        XCTAssertEqual(VisionPVTLayout.cellCenterUV(8).x, 5.0 / 6, accuracy: 1e-5)
        XCTAssertEqual(VisionPVTLayout.cellCenterUV(8).y, 5.0 / 6, accuracy: 1e-5)
    }

    func testEmptyQueue() {
        XCTAssertTrue(VisionPVTLayout.makeBalancedPeripheralQueue(count: 0).isEmpty)
    }
}
