import Foundation

enum DialogueRole: String, Codable {
  case user
  case assistant
}

struct DialogueMessage: Identifiable, Codable, Hashable {
  let id: UUID
  let role: DialogueRole
  var content: String  // Made mutable for in-place editing
  let timestamp: Date
  var durationMs: Int?  // Response latency in milliseconds

  // MARK: - Codable

  enum CodingKeys: String, CodingKey {
    case id, role, content, timestamp, durationMs
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    role = try container.decode(DialogueRole.self, forKey: .role)
    content = try container.decode(String.self, forKey: .content)
    timestamp = try container.decode(Date.self, forKey: .timestamp)
    durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(role, forKey: .role)
    try container.encode(content, forKey: .content)
    try container.encode(timestamp, forKey: .timestamp)
    try container.encodeIfPresent(durationMs, forKey: .durationMs)
  }

  init(
    id: UUID = UUID(),
    role: DialogueRole,
    content: String,
    timestamp: Date = Date(),
    durationMs: Int? = nil
  ) {
    self.id = id
    self.role = role
    self.content = content
    self.timestamp = timestamp
    self.durationMs = durationMs
  }
}
