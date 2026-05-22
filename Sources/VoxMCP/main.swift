import Foundation

if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *) {
    let server = MCPServer()
    Task { await server.run() }

    RunLoop.main.run()
}
