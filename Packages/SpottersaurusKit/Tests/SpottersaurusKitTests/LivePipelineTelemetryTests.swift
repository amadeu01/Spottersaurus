//
//  LivePipelineTelemetryTests.swift
//  SpottersaurusKitTests
//
//  Hardware-free tests for `LivePipelineTelemetry.make`: feeds plain
//  timestamp arrays and asserts the derived samples/sec, HR-flowing, and
//  staleness fields, with no CoreMotion/HealthKit dependency.
//

import Testing
@testable import SpottersaurusKit

struct LivePipelineTelemetryTests {

    // MARK: - samplesPerSecond

    @Test func samplesWithinWindowYieldExpectedRate() {
        // 50 samples evenly spread across the trailing 1s window (strictly
        // after the window floor) -> exactly 50/s.
        let timestamps = (1...50).map { Double($0) * 0.02 }
        let telemetry = LivePipelineTelemetry.make(
            motionSampleTimestamps: timestamps,
            hrSampleTimestamps: [],
            now: 1.0,
            sensorRunning: true
        )
        #expect(telemetry.samplesPerSecond == 50)
    }

    @Test func samplesOutsideWindowAreExcludedFromRate() {
        // 10 old samples well before the window, 5 recent ones inside it.
        let oldTimestamps = (0..<10).map { Double($0) * 0.02 }
        let recentTimestamps = [9.1, 9.3, 9.5, 9.7, 9.9]
        let telemetry = LivePipelineTelemetry.make(
            motionSampleTimestamps: oldTimestamps + recentTimestamps,
            hrSampleTimestamps: [],
            now: 10.0,
            sensorRunning: true,
            window: 1.0
        )
        #expect(telemetry.samplesPerSecond == 5)
    }

    @Test func noMotionSamplesYieldsZeroRateAndNilAge() {
        let telemetry = LivePipelineTelemetry.make(
            motionSampleTimestamps: [],
            hrSampleTimestamps: [],
            now: 42.0,
            sensorRunning: true
        )
        #expect(telemetry.samplesPerSecond == 0)
        #expect(telemetry.lastSampleAge == nil)
        // Sensor may still report itself started even if momentarily quiet.
        #expect(telemetry.sensorRunning == true)
    }

    // MARK: - lastSampleAge

    @Test func lastSampleAgeIsMeasuredFromNewestTimestamp() {
        let telemetry = LivePipelineTelemetry.make(
            motionSampleTimestamps: [1.0, 2.5, 4.0],
            hrSampleTimestamps: [],
            now: 5.0,
            sensorRunning: true
        )
        #expect(telemetry.lastSampleAge == 1.0)
    }

    @Test func lastSampleAgeIgnoresTimestampOrdering() {
        // Newest timestamp isn't necessarily last in the array.
        let telemetry = LivePipelineTelemetry.make(
            motionSampleTimestamps: [4.0, 1.0, 2.5],
            hrSampleTimestamps: [],
            now: 5.0,
            sensorRunning: true
        )
        #expect(telemetry.lastSampleAge == 1.0)
    }

    // MARK: - hrFlowing

    @Test func hrFlowingTrueWhenRecentSampleWithinWindow() {
        let telemetry = LivePipelineTelemetry.make(
            motionSampleTimestamps: [],
            hrSampleTimestamps: [10.0, 12.0, 14.0],
            now: 15.0,
            sensorRunning: true,
            hrWindow: 5.0
        )
        #expect(telemetry.hrFlowing == true)
    }

    @Test func hrFlowingFalseWhenLastSampleIsStale() {
        let telemetry = LivePipelineTelemetry.make(
            motionSampleTimestamps: [],
            hrSampleTimestamps: [1.0, 2.0],
            now: 20.0,
            sensorRunning: true,
            hrWindow: 5.0
        )
        #expect(telemetry.hrFlowing == false)
    }

    @Test func hrFlowingFalseWhenNoHRSamplesEverArrived() {
        let telemetry = LivePipelineTelemetry.make(
            motionSampleTimestamps: [1.0, 2.0],
            hrSampleTimestamps: [],
            now: 2.0,
            sensorRunning: true
        )
        #expect(telemetry.hrFlowing == false)
    }

    // MARK: - sensorRunning passthrough

    @Test func sensorRunningIsPassedThroughUnmodified() {
        let running = LivePipelineTelemetry.make(
            motionSampleTimestamps: [],
            hrSampleTimestamps: [],
            now: 1.0,
            sensorRunning: true
        )
        let stopped = LivePipelineTelemetry.make(
            motionSampleTimestamps: [0.5, 0.6],
            hrSampleTimestamps: [],
            now: 1.0,
            sensorRunning: false
        )
        #expect(running.sensorRunning == true)
        #expect(stopped.sensorRunning == false)
    }

    // MARK: - idle default

    @Test func idleIsAllOff() {
        #expect(LivePipelineTelemetry.idle.sensorRunning == false)
        #expect(LivePipelineTelemetry.idle.hrFlowing == false)
        #expect(LivePipelineTelemetry.idle.samplesPerSecond == 0)
        #expect(LivePipelineTelemetry.idle.lastSampleAge == nil)
    }
}
