//
//  MusicActivityWidgetBundle.swift
//  MusicActivityWidget
//
//  Created by 陈奇 on 2025/12/6.
//

import WidgetKit
import SwiftUI

@main
struct MusicActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        // 只包含 Live Activity，移除其他 Widget 以避免循环依赖
        MusicActivityWidgetLiveActivity()
    }
}
