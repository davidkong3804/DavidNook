#!/usr/bin/env python3
"""產生簡/繁專有字集的 Swift 原始碼（Sources/DavidNookCore/Chinese/GeneratedCharsets.swift）。

定義（只看 CJK 統一表意文字 U+4E00..U+9FFF）：
  簡體專有字 = GB2312 有、Big5 沒有、且 OpenCC s2t 會改它
  繁體專有字 = Big5 有、GB2312 沒有、且 OpenCC t2s 會改它
  另外排除 EXCLUDED：麽 着（原生繁體歌詞常混入）與 里后干发面台群於（兩邊通用易誤判）。

用法（在 Packages/DavidNookCore 目錄下；請勿全域 pip install，用 venv）：
  python3 -m venv /tmp/dn-charsets-venv
  /tmp/dn-charsets-venv/bin/pip install OpenCC
  /tmp/dn-charsets-venv/bin/python Tools/gen_charsets.py            # 日期用今天
  /tmp/dn-charsets-venv/bin/python Tools/gen_charsets.py --date 2026-10-05   # 可重現（固定日期）

只用到 Python 內建 codec（gb2312 / big5）與官方 PyPI 套件 OpenCC（import 名稱 opencc）。
同樣的 OpenCC 版本＋同樣的 --date 會產出逐位元相同的檔案。
"""

import argparse
import datetime
import sys
from importlib import metadata
from pathlib import Path

CJK_START = 0x4E00
CJK_END = 0x9FFF
EXCLUDED = "麽着里后干发面台群於"
LINE_WIDTH = 40  # 每行放幾個字（純排版）

DEFAULT_OUT = (
    Path(__file__).resolve().parent.parent
    / "Sources" / "DavidNookCore" / "Chinese" / "GeneratedCharsets.swift"
)


def encodable(ch: str, codec: str) -> bool:
    try:
        ch.encode(codec)
        return True
    except UnicodeEncodeError:
        return False


def build_sets(s2t, t2s):
    simplified, traditional = set(), set()
    for cp in range(CJK_START, CJK_END + 1):
        ch = chr(cp)
        in_gb = encodable(ch, "gb2312")
        in_big5 = encodable(ch, "big5")
        if in_gb and not in_big5 and s2t.convert(ch) != ch:
            simplified.add(ch)
        elif in_big5 and not in_gb and t2s.convert(ch) != ch:
            traditional.add(ch)
    for ch in EXCLUDED:
        simplified.discard(ch)
        traditional.discard(ch)
    return "".join(sorted(simplified)), "".join(sorted(traditional))


def swift_literal(chars: str, indent: str) -> str:
    """多行字串字面值；行尾的反斜線讓換行不進入字串內容。"""
    rows = [chars[i:i + LINE_WIDTH] for i in range(0, len(chars), LINE_WIDTH)]
    body = "\\\n".join(f"{indent}{row}" for row in rows)
    return f'"""\n{body}\n{indent}"""'


def render(simplified: str, traditional: str, date: str, opencc_version: str) -> str:
    return f"""\
// 由 Tools/gen_charsets.py 產生，請勿手動編輯。
//
// 產生日期：{date}
// 來源：官方 PyPI OpenCC {opencc_version}（s2t / t2s）＋ Python 內建 codec gb2312 / big5
// 簡體專有字：{len(simplified)} 個
// 繁體專有字：{len(traditional)} 個
//
// 規則（僅 U+4E00..U+9FFF）：
//   簡體專有字 = GB2312 有、Big5 沒有、且 OpenCC s2t 會改它
//   繁體專有字 = Big5 有、GB2312 沒有、且 OpenCC t2s 會改它
//   排除：{EXCLUDED}（麽 着 為原生繁體歌詞常混入；其餘為兩邊通用易誤判字）
//
// 重現方式（在 Packages/DavidNookCore 目錄下）：
//   python3 -m venv /tmp/dn-charsets-venv && /tmp/dn-charsets-venv/bin/pip install OpenCC
//   /tmp/dn-charsets-venv/bin/python Tools/gen_charsets.py --date {date}

enum GeneratedCharsets {{
    static let simplifiedOnlyCount = {len(simplified)}
    static let traditionalOnlyCount = {len(traditional)}

    /// 簡體專有字（依碼位排序）。
    static let simplifiedOnly: String = {swift_literal(simplified, "        ")}

    /// 繁體專有字（依碼位排序）。
    static let traditionalOnly: String = {swift_literal(traditional, "        ")}
}}
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="輸出的 Swift 檔路徑")
    parser.add_argument("--date", default=datetime.date.today().isoformat(), help="寫入檔頭的日期 YYYY-MM-DD（固定它即可逐位元重現）")
    args = parser.parse_args()

    try:
        from opencc import OpenCC
    except ImportError:
        print("找不到 opencc 模組。請先在 venv 內執行：pip install OpenCC", file=sys.stderr)
        return 2

    simplified, traditional = build_sets(OpenCC("s2t"), OpenCC("t2s"))
    text = render(simplified, traditional, args.date, metadata.version("OpenCC"))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text, encoding="utf-8")
    print(f"簡體專有字 {len(simplified)}、繁體專有字 {len(traditional)} → {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
