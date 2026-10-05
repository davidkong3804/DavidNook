#!/usr/bin/env python3
"""DavidNook 在地化覆蓋率檢查（只用 Python 3 標準庫，可重複執行）。

做什麼
------
1. 掃描 App 原始碼（boringNotch/**/*.swift 與 Packages/DavidNookCore/Sources/**/*.swift）中
   「會被當成在地化 key 的字面字串」：Text("…")、Label、Button、Toggle、Picker、Section、Stepper、
   TextField、MenuBarExtra、KeyboardShortcuts.Recorder、.help、.navigationTitle、.alert、
   .confirmationDialog、.accessibilityLabel/Hint、LocalizedStringKey("…")、LocalizedStringResource("…")、
   String(localized:)、NSLocalizedString、customBadge(text:)、footerText(…)。
   含字串插值（\\(x)）的字面字串會與 xcstrings 的 `%@` / `%lld` 等格式 key 以萬用字元比對。
2. 與 boringNotch/Localizable.xcstrings 比對，列出：
   A. 用到但 xcstrings 沒有這個 key
   B. 用到但缺 zh-Hant 翻譯（或翻譯為空字串）
   C. xcstrings 有這個 key，但原始碼已不再使用（孤兒 key）
   D. xcstrings 內出現 en、zh-Hant 以外的語言，或 sourceLanguage 不是 en
   E. AppKit 直接塞字面字串、完全不經在地化的 API（window.title = "…"、NSMenuItem(title: "…")、
      NSAlert 的 messageText／informativeText／addButton、toolTip、.stringValue = "…"）
3. 可選：--stringsdata <DerivedData 目錄>：把編譯器抽出的 `.stringsdata`（Xcode 以
   SWIFT_EMIT_LOC_STRINGS 產生，是 SwiftUI 在地化 key 的「真實來源」）也併入「已使用」集合，並列出
   「編譯器抽到、但本腳本的規則掃不到」的 key（代表規則有缺口）。沒有給這個參數時只靠原始碼規則。

結束碼：A～E 全為 0 時為 0，否則為 1。

用法
----
    Tools/check_localization.py                       # 專案根目錄由腳本位置推得
    Tools/check_localization.py --stringsdata build/dd # 併入編譯器資料（建議在 build 後執行）
    Tools/check_localization.py --verbose              # 另外列出每個 key 的使用位置
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

ALLOWED_LANGS = {"en", "zh-Hant"}
SENTINEL = "\u0000"  # 取代字串插值／格式化佔位符，用於比對

# 這些呼叫的「第一個字面字串引數」是在地化 key。
KEY_CALL_PREFIXES = [
    r"\bText\(\s*",  # Text(verbatim: …) 因後面不是 " 而自然被排除
    r"\bLabel\(\s*",
    r"\bButton\(\s*",
    r"\bToggle\(\s*",
    r"\bPicker\(\s*",
    r"\bSection\(\s*",
    r"\bStepper\(\s*",
    r"\bTextField\(\s*",
    r"\bColorPicker\(\s*",
    r"\bMenuBarExtra\(\s*",
    r"\bRecorder\(\s*",
    r"\.help\(\s*",
    r"\.navigationTitle\(\s*",
    r"\.alert\(\s*",
    r"\.confirmationDialog\(\s*",
    r"\.accessibilityLabel\(\s*",
    r"\.accessibilityHint\(\s*",
    r"\bLocalizedStringKey\(\s*",
    r"\bLocalizedStringResource\(\s*",
    r"\bString\(\s*localized:\s*",
    r"\bNSLocalizedString\(\s*",
    r"\bcustomBadge\(\s*text:\s*",
    r"\bfooterText\(\s*",
]
KEY_CALL_RE = re.compile("|".join(f"(?:{p})" for p in KEY_CALL_PREFIXES))

# AppKit 直接字面字串（不會被在地化）。命中就視為問題 E。
APPKIT_LITERAL_RE = re.compile(
    r"(?:\bwindow\.title\s*=\s*\"|\.title\s*=\s*\"|\bNSMenuItem\(\s*title:\s*\"|"
    r"\.messageText\s*=\s*\"|\.informativeText\s*=\s*\"|\baddButton\(\s*withTitle:\s*\"|"
    r"\.toolTip\s*=\s*\"|\.stringValue\s*=\s*\"|\.placeholderString\s*=\s*\")"
)

FORMAT_SPEC_RE = re.compile(r"%(?:\d+\$)?(?:l{0,2}[dfuxXsS@]|lld|lf)")


def parse_string_literal(src: str, i: int):
    """src[i] 必須是 "；回傳 (正規化字串, 結束位置) 或 None。插值以 SENTINEL 取代。"""
    if i >= len(src) or src[i] != '"':
        return None
    multiline = src.startswith('"""', i)
    j = i + (3 if multiline else 1)
    out: list[str] = []
    while j < len(src):
        c = src[j]
        if multiline and src.startswith('"""', j):
            return "".join(out), j + 3
        if not multiline and c == '"':
            return "".join(out), j + 1
        if not multiline and c == "\n":
            return None
        if c == "\\":
            nxt = src[j + 1] if j + 1 < len(src) else ""
            if nxt == "(":
                depth, j = 1, j + 2
                while j < len(src) and depth:
                    ch = src[j]
                    if ch == '"':  # 插值內的巢狀字串
                        nested = parse_string_literal(src, j)
                        j = nested[1] if nested else j + 1
                        continue
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                    j += 1
                out.append(SENTINEL)
                continue
            mapping = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0", "r": "\r"}
            if nxt == "u" and src.startswith("{", j + 2):
                end = src.index("}", j + 2)
                out.append(chr(int(src[j + 3 : end], 16)))
                j = end + 1
                continue
            out.append(mapping.get(nxt, nxt))
            j += 2
            continue
        out.append(c)
        j += 1
    return None


def normalize_key(key: str) -> str:
    return FORMAT_SPEC_RE.sub(SENTINEL, key)


def strip_comments(src: str) -> str:
    """把 // 與 /* */ 註解換成等長空白（保留換行，行號不變）；不動字串內容。"""
    out: list[str] = []
    i, n = 0, len(src)
    while i < n:
        if src.startswith('"""', i):
            j = src.find('"""', i + 3)
            j = n if j < 0 else j + 3
            out.append(src[i:j])
            i = j
        elif src[i] == '"':
            lit = parse_string_literal(src, i)
            j = lit[1] if lit else i + 1
            out.append(src[i:j])
            i = j
        elif src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(" " if ch != "\n" else "\n" for ch in src[i:j]))
            i = j
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def scan_file(path: Path):
    src = strip_comments(path.read_text(encoding="utf-8"))
    keys: list[tuple[str, int]] = []
    appkit: list[tuple[str, int]] = []
    for m in KEY_CALL_RE.finditer(src):
        lit = parse_string_literal(src, m.end())
        if lit is not None:
            keys.append((lit[0], src.count("\n", 0, m.end()) + 1))
    for m in APPKIT_LITERAL_RE.finditer(src):
        line = src.count("\n", 0, m.start()) + 1
        appkit.append((src[m.start() : src.find("\n", m.start())].strip()[:90], line))
    return keys, appkit


def load_stringsdata(root: Path):
    keys: dict[str, list[str]] = {}
    for f in root.rglob("*.stringsdata"):
        if "boringNotch.build" not in str(f) or "boringNotchTests" in str(f):
            continue
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for item in data.get("tables", {}).get("Localizable", []):
            src = Path(data.get("source", "?")).name
            line = item.get("location", {}).get("startingLine", "?")
            keys.setdefault(item["key"], []).append(f"{src}:{line}")
    return keys


def main() -> int:
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", type=Path, default=here.parent, help="專案根目錄（預設：腳本的上一層）")
    ap.add_argument("--stringsdata", type=Path, help="DerivedData 目錄；併入編譯器抽出的 .stringsdata")
    ap.add_argument("--verbose", action="store_true", help="列出每個 key 的使用位置")
    args = ap.parse_args()
    root: Path = args.root

    catalog_path = root / "boringNotch" / "Localizable.xcstrings"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    strings: dict = catalog["strings"]

    sources = sorted(
        list((root / "boringNotch").rglob("*.swift")) + list((root / "Packages/DavidNookCore/Sources").rglob("*.swift"))
    )
    used: dict[str, list[str]] = {}  # 規則掃到的 key（含 SENTINEL）→ 位置
    appkit_hits: list[str] = []
    for path in sources:
        rel = path.relative_to(root)
        keys, appkit = scan_file(path)
        for k, line in keys:
            used.setdefault(k, []).append(f"{rel}:{line}")
        for text, line in appkit:
            appkit_hits.append(f"{rel}:{line}: {text}")

    # 空字串與純格式 key 不需要翻譯（但仍會列出，讓人決定是否改成 verbatim）。
    catalog_norm: dict[str, str] = {}  # 正規化 key → 原 key
    for key in strings:
        catalog_norm.setdefault(normalize_key(key), key)

    compiler_keys: dict[str, list[str]] = {}
    if args.stringsdata:
        compiler_keys = load_stringsdata(args.stringsdata)

    used_norm: dict[str, list[str]] = {}
    for k, locs in used.items():
        used_norm.setdefault(k, []).extend(locs)
    compiler_only: list[str] = []
    for k, locs in compiler_keys.items():
        nk = normalize_key(k)
        if nk not in used_norm:
            compiler_only.append(k)
        used_norm.setdefault(nk, []).extend(locs)

    # A：用到但 catalog 沒有
    missing_key = sorted(k for k in used_norm if k not in catalog_norm)
    # B：缺 zh-Hant
    def zh_value(orig: str):
        loc = strings[orig].get("localizations", {}).get("zh-Hant")
        if not loc:
            return None
        unit = loc.get("stringUnit")
        if unit:
            return unit.get("value") or None
        return json.dumps(loc.get("variations") or loc.get("substitutions") or "", ensure_ascii=False) or None

    missing_zh = sorted(orig for nk, orig in catalog_norm.items() if nk in used_norm and not zh_value(orig))
    # C：孤兒
    orphans = sorted(orig for nk, orig in catalog_norm.items() if nk not in used_norm)
    # D：語言
    langs: set[str] = set()
    for v in strings.values():
        langs.update(v.get("localizations", {}).keys())
    bad_langs = sorted(langs - ALLOWED_LANGS)
    bad_source = catalog.get("sourceLanguage") != "en"

    def show(k: str) -> str:
        return k.replace(SENTINEL, "%@").replace("\n", "\\n")

    def section(title: str, items: list[str], locs=None) -> None:
        print(f"\n[{title}] {len(items)}")
        for it in items:
            where = ""
            if args.verbose and locs is not None:
                where = "  <- " + ", ".join(locs.get(it, [])[:3])
            print(f"  - {show(it)}{where}")

    print(f"原始碼檔案 {len(sources)} 個；xcstrings key {len(strings)} 個；規則掃到的在地化字面字串 {len(used)} 種"
          + (f"；編譯器 .stringsdata key {len(compiler_keys)} 個" if compiler_keys else ""))
    print(f"語言：{sorted(langs)}；sourceLanguage={catalog.get('sourceLanguage')!r}")

    section("A 用到但 xcstrings 沒有的 key", missing_key, used_norm)
    section("B 用到但缺 zh-Hant 翻譯", missing_zh, used_norm)
    section("C xcstrings 有、原始碼已不使用（孤兒 key）", orphans)
    print(f"\n[D 非 en／zh-Hant 的語言或 sourceLanguage 錯誤] {len(bad_langs) + int(bad_source)}")
    for lang in bad_langs:
        print(f"  - 語言 {lang}")
    if bad_source:
        print(f"  - sourceLanguage = {catalog.get('sourceLanguage')!r}（應為 'en'）")
    print(f"\n[E AppKit 直接字面字串（未在地化）] {len(appkit_hits)}")
    for hit in appkit_hits:
        print(f"  - {hit}")
    if compiler_keys:
        print(f"\n[資訊] 編譯器抽到、但規則掃不到的 key（規則缺口；不計入失敗）: {len(compiler_only)}")
        for k in sorted(compiler_only):
            print(f"  - {show(k)}  <- {', '.join(compiler_keys[k][:2])}")

    total = len(missing_key) + len(missing_zh) + len(orphans) + len(bad_langs) + int(bad_source) + len(appkit_hits)
    print("\n" + "=" * 60)
    print(f"缺 zh-Hant（A+B）= {len(missing_key) + len(missing_zh)}；孤兒 key（C）= {len(orphans)}；"
          f"其他語言（D）= {len(bad_langs) + int(bad_source)}；AppKit 未在地化（E）= {len(appkit_hits)}")
    print("結果：" + ("通過" if total == 0 else "未通過"))
    return 0 if total == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
