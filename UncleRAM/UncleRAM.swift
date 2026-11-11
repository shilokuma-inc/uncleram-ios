//
//  UncleRAM.swift
//  UncleRAM
//
//  Created by 村石 拓海 on 2024/05/12.
//

import SwiftUI

@main
struct UncleRAM: App {
    var body: some Scene {
        #if os(macOS)
        // Mac はウィンドウを 1 つに限る（docs/SPEC.md「ラウンドの状態と中断」）
        Window(Text(verbatim: "Uncle RAM"), id: "main") {
            rootView
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1200, height: 760)
        .windowResizability(.contentMinSize)
        #else
        WindowGroup {
            rootView
        }
        #endif
    }

    /// 撮影モード（ScreenshotDemo）のときは、撮る画面を開く
    @ViewBuilder private var rootView: some View {
        switch ScreenshotDemo.scene {
        case .home, nil:
            RoundScreen()
        }
    }
}
