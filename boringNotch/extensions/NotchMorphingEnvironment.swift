//
//  NotchMorphingEnvironment.swift
//  DavidNook
//
//  「瀏海正在變形」的環境值：展開／收合／切分頁／拖動尺寸滑桿期間為 true，由 ContentView 設定。
//  昂貴或高頻更新的子視圖（例如歌詞面板的 TimelineView）讀它來降低更新頻率，變形結束後自動恢復。
//

import SwiftUI

private struct NotchIsMorphingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notchIsMorphing: Bool {
        get { self[NotchIsMorphingKey.self] }
        set { self[NotchIsMorphingKey.self] = newValue }
    }
}
