import WidgetKit
import SwiftUI

@main
struct MusicActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            MusicActivityWidget()
        }
    }
}
