import Foundation

struct TerminalTab: Identifiable {
    let id: String
    var title: String

    init(id: String = UUID().uuidString, title: String = "Terminal") {
        self.id = id
        self.title = title
    }
}
