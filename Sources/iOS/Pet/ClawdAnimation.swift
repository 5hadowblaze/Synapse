import Foundation
import UIKit

/// Animation states from `clawd-pet-package` (see animation-spec.json / TUTORIAL.md).
enum ClawdAnimState: String, CaseIterable, Sendable {
    case idle
    case runningRight = "running-right"
    case runningLeft = "running-left"
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review

    var isOneShot: Bool {
        self == .jumping || self == .failed
    }
}

struct ClawdAnimClip: Sendable {
    let state: ClawdAnimState
    let row: Int
    let frames: Int
    let fps: Double
    let loop: Bool
}

/// Loads the Clawd atlas + clips; crops frames on demand (cached).
@MainActor
final class ClawdAtlas {
    static let shared = ClawdAtlas()

    private let cellWidth = 192
    private let cellHeight = 208
    private let columns = 8

    private(set) var sheet: CGImage?
    private(set) var clips: [ClawdAnimState: ClawdAnimClip] = [:]
    private var frameCache: [String: UIImage] = [:]

    private init() {
        load()
    }

    func clip(for state: ClawdAnimState) -> ClawdAnimClip {
        clips[state] ?? ClawdAnimClip(state: .idle, row: 0, frames: 6, fps: 6, loop: true)
    }

    func frameImage(state: ClawdAnimState, index: Int) -> UIImage? {
        let clip = clip(for: state)
        let i = max(0, min(index, clip.frames - 1))
        let key = "\(state.rawValue)-\(i)"
        if let cached = frameCache[key] { return cached }
        guard let sheet else { return nil }
        let x = i * cellWidth
        let y = clip.row * cellHeight
        guard let cropped = sheet.cropping(
            to: CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
        ) else { return nil }
        let image = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        frameCache[key] = image
        return image
    }

    private func load() {
        // Built-in defaults from the package if JSON missing.
        let defaults: [ClawdAnimClip] = [
            .init(state: .idle, row: 0, frames: 6, fps: 6, loop: true),
            .init(state: .runningRight, row: 1, frames: 8, fps: 12, loop: true),
            .init(state: .runningLeft, row: 2, frames: 8, fps: 12, loop: true),
            .init(state: .waving, row: 3, frames: 4, fps: 8, loop: true),
            .init(state: .jumping, row: 4, frames: 5, fps: 10, loop: false),
            .init(state: .failed, row: 5, frames: 8, fps: 10, loop: false),
            .init(state: .waiting, row: 6, frames: 6, fps: 6, loop: true),
            .init(state: .running, row: 7, frames: 6, fps: 8, loop: true),
            .init(state: .review, row: 8, frames: 6, fps: 8, loop: true),
        ]
        for clip in defaults {
            clips[clip.state] = clip
        }

        if let url = Bundle.main.url(forResource: "clawd-animation-spec", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let states = json["states"] as? [[String: Any]] {
            for entry in states {
                guard let name = entry["state"] as? String,
                      let state = ClawdAnimState(rawValue: name),
                      let row = entry["row"] as? Int,
                      let frames = entry["frames"] as? Int else { continue }
                let fps = (entry["fps"] as? Double) ?? Double(entry["fps"] as? Int ?? 8)
                let loop = entry["loop"] as? Bool ?? true
                clips[state] = ClawdAnimClip(state: state, row: row, frames: frames, fps: fps, loop: loop)
            }
        }

        let candidates = ["clawd-spritesheet", "spritesheet"]
        for name in candidates {
            if let img = UIImage(named: name), let cg = img.cgImage {
                sheet = cg
                break
            }
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data),
               let cg = img.cgImage {
                sheet = cg
                break
            }
        }
    }
}
