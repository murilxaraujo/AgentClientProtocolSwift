import Foundation

// MARK: - Permission Types

/// The type of permission option being presented to the user.
///
/// Helps clients choose appropriate icons and UI treatment.
public enum PermissionOptionKind: String, Codable, Sendable, Hashable {
    /// Allow the action this one time only
    case allowOnce = "allow_once"
    /// Allow the action always (remember the permission)
    case allowAlways = "allow_always"
    /// Reject the action this one time only
    case rejectOnce = "reject_once"
    /// Reject the action always (remember the rejection)
    case rejectAlways = "reject_always"
}

/// An option presented to the user when requesting permission.
///
/// Used by agents to present permission choices to the user for sensitive operations.
public struct PermissionOption: AcpWithMeta, Codable, Sendable, Hashable {
    /// Unique identifier for this option
    public let optionId: PermissionOptionId

    /// Human-readable name for the option
    public let name: String

    /// The kind of permission this option represents
    public let kind: PermissionOptionKind

    /// Optional metadata
    public let _meta: MetaField? // swiftlint:disable:this identifier_name

    /// Creates a permission option.
    ///
    /// - Parameters:
    ///   - optionId: Unique identifier
    ///   - name: Human-readable name
    ///   - kind: The permission kind
    ///   - meta: Optional metadata
    public init(
        optionId: PermissionOptionId,
        name: String,
        kind: PermissionOptionKind,
        meta: MetaField? = nil
    ) {
        self.optionId = optionId
        self.name = name
        self.kind = kind
        self._meta = meta
    }

    private enum CodingKeys: String, CodingKey {
        case optionId = "optionId"
        case name = "name"
        case kind = "kind"
        case _meta = "_meta" // swiftlint:disable:this identifier_name
    }
}

// MARK: - Permission Outcome

/// The outcome of a permission request.
///
/// Indicates how the user responded to the permission request.
public enum RequestPermissionOutcome: Codable, Sendable, Hashable {
    /// The prompt turn was cancelled before the user responded
    case cancelled
    /// The user selected one of the provided options
    case selected(PermissionOptionId)

    private enum CodingKeys: String, CodingKey {
        case outcome = "outcome"
        case optionId = "optionId"
    }

    private enum OutcomeType: String, Codable {
        case cancelled = "cancelled"
        case selected = "selected"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outcomeType = try container.decode(OutcomeType.self, forKey: .outcome)

        switch outcomeType {
        case .cancelled:
            self = .cancelled
        case .selected:
            let optionId = try container.decode(PermissionOptionId.self, forKey: .optionId)
            self = .selected(optionId)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .cancelled:
            try container.encode(OutcomeType.cancelled, forKey: .outcome)
        case .selected(let optionId):
            try container.encode(OutcomeType.selected, forKey: .outcome)
            try container.encode(optionId, forKey: .optionId)
        }
    }
}

// MARK: - Request Permission Request

/// Request for user permission to execute a tool call.
///
/// Sent when the agent needs authorization before performing a sensitive operation.
/// Supports both v1 wire format (bare `toolCall`) and v2 wire format (`subject.toolCall`
/// with top-level `title`/`description`).
///
/// See protocol docs: [Requesting Permission](https://agentclientprotocol.com/protocol/tool-calls#requesting-permission)
public struct RequestPermissionRequest: AcpRequest, AcpWithSessionId, Codable, Sendable, Hashable {
    /// The session this request belongs to
    public let sessionId: SessionId

    /// The tool call that needs permission
    public let toolCall: ToolCallUpdateData

    /// The permission options to present to the user
    public let options: [PermissionOption]

    /// Human-readable title for the permission prompt (v2 format only)
    public let title: String?

    /// Optional description of the action requiring permission (v2 format only)
    public let description: String?

    /// Optional metadata
    public let _meta: MetaField? // swiftlint:disable:this identifier_name

    /// Creates a permission request.
    ///
    /// - Parameters:
    ///   - sessionId: The session ID
    ///   - toolCall: The tool call needing permission
    ///   - options: Available permission options
    ///   - title: Human-readable title (v2)
    ///   - description: Optional description (v2)
    ///   - meta: Optional metadata
    public init(
        sessionId: SessionId,
        toolCall: ToolCallUpdateData,
        options: [PermissionOption],
        title: String? = nil,
        description: String? = nil,
        meta: MetaField? = nil
    ) {
        self.sessionId = sessionId
        self.toolCall = toolCall
        self.options = options
        self.title = title
        self.description = description
        self._meta = meta
    }

    // v2 subject wrapper: { "type": "tool_call", "toolCall": { ... } }
    private struct SubjectData: Decodable {
        let toolCall: ToolCallUpdateData
        enum CodingKeys: String, CodingKey {
            case toolCall
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId = "sessionId"
        case toolCall = "toolCall"
        case subject = "subject"
        case title = "title"
        case description = "description"
        case options = "options"
        case _meta = "_meta" // swiftlint:disable:this identifier_name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(SessionId.self, forKey: .sessionId)
        // v2: toolCall is nested inside subject; v1: toolCall is at the top level
        if let subject = try container.decodeIfPresent(SubjectData.self, forKey: .subject) {
            toolCall = subject.toolCall
        } else {
            toolCall = try container.decode(ToolCallUpdateData.self, forKey: .toolCall)
        }
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        options = try container.decode([PermissionOption].self, forKey: .options)
        _meta = try container.decodeIfPresent(MetaField.self, forKey: ._meta)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(toolCall, forKey: .toolCall)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(options, forKey: .options)
        try container.encodeIfPresent(_meta, forKey: ._meta)
    }
}

// MARK: - Request Permission Response

/// Response to a permission request.
///
/// Contains the user's decision about the permission request.
public struct RequestPermissionResponse: AcpResponse, Codable, Sendable, Hashable {
    /// The outcome of the permission request
    public let outcome: RequestPermissionOutcome

    /// Optional metadata
    public let _meta: MetaField? // swiftlint:disable:this identifier_name

    /// Creates a permission response.
    ///
    /// - Parameters:
    ///   - outcome: The user's decision
    ///   - meta: Optional metadata
    public init(outcome: RequestPermissionOutcome, meta: MetaField? = nil) {
        self.outcome = outcome
        self._meta = meta
    }

    private enum CodingKeys: String, CodingKey {
        case outcome = "outcome"
        case _meta = "_meta" // swiftlint:disable:this identifier_name
    }
}
