# 0.3.0 功能路線圖（2026-10-13 使用者核准：全做）

## 原則
- 本機優先。**聯網功能一律預設關**（使用者在設定打開才連），只連固定的公開服務、不用帳號與金鑰、不送個資；設定頁列出所有對外連線。**不做 AI 助理／摘要這類功能。**
- 不新增權限／entitlement，除非該功能必需且使用者核准（行事曆＝EventKit 需 `personal-information.calendars` 並在 Info.plist 加用途字串；先問）。
- 視窗永遠不 setFrame（見 NotchWindowManager 註解）。新內容都在固定視窗範圍內排版。
- 小按鈕問題：任何可點元件至少 30pt 見方。
- 流程：Core 純邏輯 TDD（紅燈 commit 先）→ UI 度量／視圖 → App 接線 → xcstrings（只 en＋zh-Hant）→ `Tools/check_localization.py` 全 0 → build_release 成功。

## 分頁架構決定
分頁列：**播放｜剪貼簿｜番茄鐘｜工具**。「工具」分頁內有子頁切換（工具列內的小分段控制）：
**日曆（月曆＋倒數日＋課表）｜計算機（含匯率）｜便利貼｜天氣**。
子頁選擇與各子頁資料只存數字／文字設定於 Defaults（便利貼內容存本機，不上傳）。

## 切片順序（每片獨立 agent、獨立 worktree，依賴者等前一片合併）
0. 番茄鐘分頁（進行中：agent a131fb60d0dc68d1f）。
1. 剪貼簿圖片文字辨識（Vision，本機；只動 Clipboard*）——可與 0 並行。
2. 「工具」分頁骨架＋計算機（NSExpression 風格自寫解析器，純 Core，可測）＋匯率（Frankfurter，聯網，預設關）。
3. 日曆：月曆＋倒數日＋課表（課表本機手動輸入；EventKit 事件顯示為選用，需先問權限）。
4. 天氣（Open-Meteo，聯網，預設關，城市手動選）。
5. 便利貼。
6. 番茄鐘連動專注模式：開始／結束時以 `shortcuts://run-shortcut?name=…` 執行使用者指定的「捷徑」（無公開 API 可直接切專注模式；沙盒內不能跑 shortcuts CLI）。
7. 自動檢查更新（選用，預設關，每天最多一次）。
8. 發布 0.3.0-beta.1（版本號＝tag；`Tools/package_release.sh`）。
