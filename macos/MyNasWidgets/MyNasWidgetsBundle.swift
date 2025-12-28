//
//  MyNasWidgetsBundle.swift
//  MyNasWidgets
//
//  Created by 陈奇 on 2025/12/28.
//

import WidgetKit
import SwiftUI

@main
struct MyNasWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickAccessWidget()
        StorageWidget()
        DownloadWidget()
        MediaWidget()
    }
}
