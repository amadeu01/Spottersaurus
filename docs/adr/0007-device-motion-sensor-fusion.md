# Upgrade the motion feed to fused device motion (gravity, attitude, rotation)

Date: 2026-07-10
Status: Accepted

## Context

Detection currently ingests only the **raw accelerometer** stream
(`CMBatchedSensorManager.accelerometerUpdates()`, 800 Hz) and recovers the bar
axis with an EMA gravity estimate in `GravityRemover`. That throws away signals
the hardware already provides and makes the weak squat path (and the
unrack/walkout rejection of ADR 0006) harder than they need to be. Apple's
`CMBatchedSensorManager.deviceMotionUpdates()` delivers **fused device motion at
200 Hz**: `gravity`, `userAcceleration` (gravity removed via accel+gyro sensor
fusion), `attitude`, and `rotationRate`.

## Decision

- **Stream fused device motion** as the primary source: switch the Watch feed to
  `deviceMotionUpdates()`; keep `accelerometerUpdates()` / `CMMotionManager` as
  fallbacks. Use every sensor CoreMotion fuses here — accelerometer **and
  gyroscope** — since the goal is maximum accuracy.
- **Carry the richer sample into Kit.** Add a device-motion sample type
  (timestamp + `userAcceleration`, `gravity`, `rotationRate`, `attitude`) beside
  `MotionSample`, all pure/Codable so the engine stays macOS-testable against
  recorded/synthetic buffers.
- **Use the fused data in detection:** project onto the CoreMotion-provided
  gravity vector (drop the EMA hack when gravity is present; keep it as a
  fallback for raw-accel-only sources and tests); use `rotationRate`/`attitude`
  to reject non-rep motion (walkout, torso sway) and to sharpen the squat path
  and the ADR 0006 rep-1 gate.
- **Barometer/altimeter** (`CMAltimeter`, ~1 Hz) is noted as a possible future
  ROM-confirmation signal but is out of scope now (too slow for rep speed).

## Consequences

- The detection pipeline gains a second sample type; `GravityRemover` becomes one
  of two front ends (fused vs raw). Tests must cover both.
- The Watch adapter change (`deviceMotionUpdates`) is device-side and not
  macOS-testable — its Kit-side consumers (sample type, projection, rotation
  gating) are, and carry the test weight.
