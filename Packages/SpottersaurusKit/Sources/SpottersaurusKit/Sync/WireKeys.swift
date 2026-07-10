//
//  WireKeys.swift
//  SpottersaurusKit
//
//  Single source of truth for the `WCSession` message/application-context/
//  userInfo dictionary keys shared by the iPhone (`WatchLink`) and Watch
//  (`WatchPlannedSessionStore`) sides of the transport. Previously these were
//  private string literals duplicated on both sides of the link, kept in
//  sync only by a comment — a rename on one side compiled fine and silently
//  broke the wire contract at runtime. These are the WIRE keys only; local
//  persistence keys (e.g. `UserDefaults` / `HealthKitAuthorizer` flags) are
//  NOT part of this contract and must not be added here.
//
public enum WireKeys {
    /// Keyed payload for a `PlannedSessionEnvelope` sent iPhone -> Watch via
    /// `updateApplicationContext`/`transferUserInfo`.
    public static let plannedSession = "plannedSession"
    /// Keyed payload for a `WatchCommandEnvelope` sent iPhone -> Watch via
    /// `sendMessage`.
    public static let watchCommand = "watchCommand"
    /// Keyed payload for a finished `SessionEnvelope` sent Watch -> iPhone.
    public static let finishedSession = "finishedSession"
    /// Keyed payload for a `LiveSetLifecycleEnvelope` sent Watch -> iPhone.
    public static let liveSetLifecycle = "liveSetLifecycle"
    /// Keyed payload for a live tick, reserved for the keyed transport path.
    /// The current live-tick send/receive path uses bare `sendMessageData`
    /// (no key) — see `WatchLink.receiveLiveTick`/`WatchPlannedSessionStore
    /// .transmit` — but this constant is retained as part of the wire
    /// contract so any future keyed live-tick path stays pinned to one
    /// string.
    public static let liveTick = "liveTick"
}
