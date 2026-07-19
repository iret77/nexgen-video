public enum EngineContract {
    /// Bump whenever anything crossing the host↔pack binary boundary changes shape — a `Pack`
    /// protocol requirement, a type in its signatures, `PackEntry`. A pack built against a
    /// different value is refused at load; it cannot be called safely.
    public static let current = 2
}
