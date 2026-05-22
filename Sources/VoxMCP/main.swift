import Foundation

let server = MCPServer()

Task { await server.run() }

RunLoop.main.run()
