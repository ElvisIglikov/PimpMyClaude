@testable import ClaudeAX

/// Unit fixtures never discover or address a developer's running Claude. Tests of process
/// selection may explicitly replace these hooks with their own fake instances afterwards.
enum IsolatedClaudeApp {
    static func make() -> ClaudeApp {
        let app = ClaudeApp()
        app.instances = { [] }
        app.windowOwners = { [] }
        return app
    }
}
