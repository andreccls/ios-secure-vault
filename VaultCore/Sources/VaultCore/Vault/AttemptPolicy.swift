import Foundation

public struct AttemptState: Codable, Equatable, Sendable {
  public var failures: Int
  public var lastFailure: Date?

  public init(failures: Int = 0, lastFailure: Date? = nil) {
    self.failures = failures
    self.lastFailure = lastFailure
  }
}

/// Exponential backoff after repeated wrong master passwords: 3 free tries, then 2 s, 4 s, 8 s... capped at 5 min.
/// This only slows down someone using the app's UI; an offline attacker with the files is limited by PBKDF2 alone.
public struct AttemptPolicy: Sendable {
  public let freeAttempts: Int
  public let baseDelay: TimeInterval
  public let maxDelay: TimeInterval

  public init(freeAttempts: Int = 3, baseDelay: TimeInterval = 2, maxDelay: TimeInterval = 300) {
    self.freeAttempts = freeAttempts
    self.baseDelay = baseDelay
    self.maxDelay = maxDelay
  }

  public func delay(afterFailures failures: Int) -> TimeInterval {
    guard failures > freeAttempts else { return 0 }
    return min(baseDelay * pow(2, Double(min(failures - freeAttempts - 1, 20))), maxDelay)
  }

  public func retryAfter(_ state: AttemptState, now: Date) -> TimeInterval {
    guard let last = state.lastFailure else { return 0 }
    return max(0, last.addingTimeInterval(delay(afterFailures: state.failures)).timeIntervalSince(now))
  }
}
