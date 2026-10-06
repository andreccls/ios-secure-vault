import Foundation
import os

public struct VaultHeader: Codable, Equatable, Sendable {
  public var version: Int
  public var kdf: String
  public var iterations: Int
  public var salt: Data
  /// DEK sealed with the KEK (AES-GCM, see `Vault`).
  public var wrappedDEK: Data
  /// A known plaintext sealed with the DEK; lets us validate a DEK obtained elsewhere (biometric keychain).
  public var keyCheck: Data
}

/// Persistence port: opaque blobs plus the small non-secret header. Implementations never see plaintext.
public protocol VaultStorage: Sendable {
  func loadHeader() throws -> VaultHeader?
  func saveHeader(_ header: VaultHeader) throws
  func loadRecords() throws -> [UUID: Data]
  func saveRecord(_ data: Data, id: UUID) throws
  func deleteRecord(id: UUID) throws
  func loadAttempts() throws -> AttemptState
  func saveAttempts(_ state: AttemptState) throws
}

/// Test/preview double.
public final class InMemoryVaultStorage: VaultStorage {
  private struct State {
    var header: VaultHeader?
    var records: [UUID: Data] = [:]
    var attempts = AttemptState()
  }
  private let state = OSAllocatedUnfairLock(initialState: State())

  public init() {}
  public func loadHeader() throws -> VaultHeader? { state.withLock { $0.header } }
  public func saveHeader(_ header: VaultHeader) throws { state.withLock { $0.header = header } }
  public func loadRecords() throws -> [UUID: Data] { state.withLock { $0.records } }
  public func saveRecord(_ data: Data, id: UUID) throws { state.withLock { $0.records[id] = data } }
  public func deleteRecord(id: UUID) throws { state.withLock { _ = $0.records.removeValue(forKey: id) } }
  public func loadAttempts() throws -> AttemptState { state.withLock { $0.attempts } }
  public func saveAttempts(_ value: AttemptState) throws { state.withLock { $0.attempts = value } }
}
