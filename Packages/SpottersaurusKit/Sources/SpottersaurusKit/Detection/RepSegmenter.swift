//
//  RepSegmenter.swift
//  SpottersaurusKit
//
//  Splits a bar-axis acceleration stream (gravity removed) into reps with
//  eccentric / concentric phases. The approach: integrate axial acceleration to
//  a velocity trace with a zero-velocity update (ZUPT) at the low-motion points
//  between reps, then read phases off the velocity sign — a concentric is an
//  upward (positive-velocity) excursion, an eccentric a downward one. Pure math,
//  no hardware, driven entirely off sample timestamps.
//

import Foundation

/// One detected rep's phase timings. Timestamps are seconds since set-arm.
public struct RepPhase: Sendable, Equatable {
    /// Zero-based rep order within the buffer (assigned by the segmenter).
    public var index: Int
    public var concentricStart: TimeInterval
    public var concentricEnd: TimeInterval
    /// Eccentric bounds when one was detected in the same motion bout.
    public var eccentricStart: TimeInterval?
    public var eccentricEnd: TimeInterval?

    public init(
        index: Int,
        concentricStart: TimeInterval,
        concentricEnd: TimeInterval,
        eccentricStart: TimeInterval? = nil,
        eccentricEnd: TimeInterval? = nil
    ) {
        self.index = index
        self.concentricStart = concentricStart
        self.concentricEnd = concentricEnd
        self.eccentricStart = eccentricStart
        self.eccentricEnd = eccentricEnd
    }

    /// Concentric (lifting-phase) duration in seconds.
    public var concentricSeconds: Double { concentricEnd - concentricStart }
    /// Eccentric (lowering-phase) duration in seconds, 0 when none was found.
    public var eccentricSeconds: Double {
        guard let s = eccentricStart, let e = eccentricEnd else { return 0 }
        return e - s
    }
}

/// Segments a motion stream into reps. Stateless apart from its tuning config.
public struct RepSegmenter: Sendable {
    public var config: SpotConfig

    public init(config: SpotConfig = .conservative) {
        self.config = config
    }

    /// Convenience: gravity-remove a raw accelerometer stream, then segment.
    public func segment(motion: [MotionSample]) -> [RepPhase] {
        segment(GravityRemover.axialAcceleration(motion, timeConstant: config.gravityTimeConstant))
    }

    /// Segments a bar-axis linear-acceleration stream into reps.
    public func segment(_ linear: [LinearSample]) -> [RepPhase] {
        guard linear.count >= 2 else { return [] }

        let still = stillMask(linear)
        let v = integratedVelocity(linear, still: still)

        var phases: [RepPhase] = []
        var i = 0
        let n = linear.count

        // Walk motion bouts (contiguous non-still regions); within each, read
        // off one phase per upward (concentric) velocity excursion.
        while i < n {
            if still[i] { i += 1; continue }
            var j = i
            while j < n && !still[j] { j += 1 }
            phases.append(contentsOf: concentrics(in: linear, velocity: v, lo: i, hi: j))
            i = j
        }

        // Assign global rep order.
        for k in phases.indices { phases[k].index = k }
        return phases
    }

    // MARK: - Velocity trace with ZUPT

    /// Trapezoidal integration of axial acceleration, clamped to zero whenever
    /// the still detector says the bar is at rest. The ZUPT keeps integration
    /// drift bounded to a single rep instead of accumulating across the set.
    func integratedVelocity(_ linear: [LinearSample], still: [Bool]) -> [Double] {
        var v = [Double](repeating: 0, count: linear.count)
        guard linear.count > 1 else { return v }
        for i in 1..<linear.count {
            if still[i] { v[i] = 0; continue }
            let dt = linear[i].timestamp - linear[i - 1].timestamp
            let prev = still[i - 1] ? 0 : v[i - 1]
            v[i] = prev + 0.5 * (linear[i].axialMS2 + linear[i - 1].axialMS2) * dt
        }
        return v
    }

    // MARK: - Still detection

    /// True where the bar is racked / paused. A sample is "quiet" when its
    /// |acceleration| is under the threshold; it only counts as *still* when it
    /// belongs to a quiet run that lasts at least `minStillSeconds`. That gate
    /// is what separates a real rest from the momentary low-acceleration point
    /// at a rep's velocity peak (the bar is moving fast there, not still) — which
    /// otherwise chops slow grinds into pieces.
    func stillMask(_ linear: [LinearSample]) -> [Bool] {
        let n = linear.count
        var mask = [Bool](repeating: false, count: n)
        let threshold = config.stillAccelThresholdMS2

        var i = 0
        while i < n {
            if abs(linear[i].axialMS2) >= threshold { i += 1; continue }
            var j = i
            while j < n && abs(linear[j].axialMS2) < threshold { j += 1 }
            let duration = linear[j - 1].timestamp - linear[i].timestamp
            if duration >= config.minStillSeconds {
                for k in i..<j { mask[k] = true }
            }
            i = j
        }
        return mask
    }

    // MARK: - Phase extraction within a bout

    /// Extracts concentric windows from one motion bout `[lo, hi)`. A concentric
    /// opens when velocity rises above the move threshold and runs until either a
    /// downward reversal (the next eccentric) or the end of the bout (a settle /
    /// rack). A stalled bar that hovers near zero is therefore *kept inside* the
    /// concentric — exactly the region the pin detector needs.
    func concentrics(in linear: [LinearSample], velocity v: [Double], lo: Int, hi: Int) -> [RepPhase] {
        var result: [RepPhase] = []
        let move = config.moveThresholdMS
        var k = lo

        while k < hi {
            if v[k] <= move { k += 1; continue }
            let startIdx = k

            // Advance until a sustained downward reversal or the bout end.
            var e = startIdx
            while e < hi && v[e] >= -move { e += 1 }
            let endIdx = (e < hi) ? e - 1 : hi - 1

            let start = linear[startIdx].timestamp
            let end = linear[endIdx].timestamp
            if end - start >= config.minPhaseSeconds {
                let (es, ee) = eccentric(before: startIdx, lo: lo, velocity: v, linear: linear)
                result.append(
                    RepPhase(
                        index: -1,
                        concentricStart: start,
                        concentricEnd: end,
                        eccentricStart: es,
                        eccentricEnd: ee
                    )
                )
            }

            // Resume past this concentric, skipping the descending region.
            k = Swift.max(endIdx + 1, e)
            while k < hi && v[k] < move { k += 1 }
        }
        return result
    }

    /// Best-effort eccentric window immediately preceding a concentric: the most
    /// recent maximal run of downward (negative) velocity within the bout.
    func eccentric(before startIdx: Int, lo: Int, velocity v: [Double], linear: [LinearSample]) -> (TimeInterval?, TimeInterval?) {
        let move = config.moveThresholdMS
        var k = startIdx - 1
        while k >= lo && v[k] >= -move { k -= 1 }
        guard k >= lo else { return (nil, nil) }
        let endIdx = k
        while k > lo && v[k - 1] < -move { k -= 1 }
        let startIdxEcc = k
        return (linear[startIdxEcc].timestamp, linear[endIdx].timestamp)
    }
}
