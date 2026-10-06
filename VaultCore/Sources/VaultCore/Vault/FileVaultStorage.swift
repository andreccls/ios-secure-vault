import Foundation

/// One directory: `header.json`, `attempts.json` and one `<uuid>.item` ciphertext file per item.
/// File names leak the item count and ids/mtimes (documented trade-off, ADR 0006). The directory is excluded from
/// iCloud/iTunes backups and, on iOS, files use complete data protection (unreadable while the device is locked).
public final class FileVaultStorage: VaultStorage {
  private let directory: URL
  private var fileManager: FileManager { .default }

  public init(directory: URL) { self.directory = directory }

  private var headerURL: URL { directory.appendingPathComponent("header.json") }
  private var attemptsURL: URL { directory.appendingPathComponent("attempts.json") }
  private func recordURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).item") }

  private func write(_ data: Data, to url: URL) throws {
    try ensureDirectory()
    #if os(iOS)
      try data.write(to: url, options: [.atomic, .completeFileProtection])
    #else
      try data.write(to: url, options: .atomic)
    #endif
  }

  private func ensureDirectory() throws {
    guard !fileManager.fileExists(atPath: directory.path) else { return }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    var url = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }

  public func loadHeader() throws -> VaultHeader? {
    guard fileManager.fileExists(atPath: headerURL.path) else { return nil }
    return try JSONDecoder().decode(VaultHeader.self, from: Data(contentsOf: headerURL))
  }

  public func saveHeader(_ header: VaultHeader) throws {
    try write(JSONEncoder().encode(header), to: headerURL)
  }

  public func loadRecords() throws -> [UUID: Data] {
    guard fileManager.fileExists(atPath: directory.path) else { return [:] }
    var records: [UUID: Data] = [:]
    for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    where url.pathExtension == "item" {
      guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
      records[id] = try Data(contentsOf: url)
    }
    return records
  }

  public func saveRecord(_ data: Data, id: UUID) throws { try write(data, to: recordURL(id)) }

  public func deleteRecord(id: UUID) throws {
    let url = recordURL(id)
    if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
  }

  public func loadAttempts() throws -> AttemptState {
    guard fileManager.fileExists(atPath: attemptsURL.path) else { return AttemptState() }
    return try JSONDecoder().decode(AttemptState.self, from: Data(contentsOf: attemptsURL))
  }

  public func saveAttempts(_ state: AttemptState) throws {
    try write(JSONEncoder().encode(state), to: attemptsURL)
  }

  /// Removes the whole vault directory (used by tests and UI-test resets).
  public func wipe() throws {
    if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
  }
}
