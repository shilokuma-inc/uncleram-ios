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

    /// 撮影モード（ScreenshotDemo）のラウンドの場面と計測のときは、タイトルを通さずにラウンド画面を開く（AppRoot）
    @ViewBuilder private var rootView: some View {
        AppRoot()
            // 文字は「さらに大きな文字」を使わない範囲（xxxLarge、本文で約 135%）まで大きくする。
            // ラウンドは長押しで遊ぶので、スクロールさせずに 1 画面に収める（2026-11-26 にユーザーが決定）
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
