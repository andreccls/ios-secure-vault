import Foundation

public enum AutoLockTimeout: Int, CaseIterable, Codable, Sendable {
  case thirtySeconds = 30
  case oneMinute = 60
  case fiveMinutes = 300
  case fifteenMinutes = 900

  public var seconds: TimeInterval { TimeInterval(rawValue) }
}

/// Pure inactivity logic: the caller supplies "now", so tests (and the app) own the clock.
/// Going to the background is handled by the app (it locks immediately, no grace period).
public struct InactivityMonitor: Sendable {
  public var timeout: AutoLockTimeout
  private var lastActivity: Date

  public init(timeout: AutoLockTimeout, now: Date) {
    self.timeout = timeout
    self.lastActivity = now
  }

  public mutating func recordActivity(at now: Date) { lastActivity = now }

  public func isExpired(at now: Date) -> Bool {
    now.timeIntervalSince(lastActivity) >= timeout.seconds
  }
}
