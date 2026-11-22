#!/usr/bin/env python3
"""WorldCapture · Sparkle appcast 校验（release.sh 第 10 步调用；失败即非零退出）。

为什么要有它：generate_appcast 会把「已有条目」的下载地址也改写成本次版本的前缀（2026-10-07 实测），
旧版本的 DMG/增量包随之指向一个不存在的地址——老用户升级直接失败，而脚本照样报「完成」。

检查项：
  1. 本次版本的条目存在，主 DMG 的 length 与本地文件字节数一致；
  2. 每个条目（含增量包）的下载地址都落在**自己版本**的 tag 目录 .../releases/download/v<版本>/；
  3. 本地目录里有的附件，length 必须与文件字节数一致；本次版本引用的附件必须在本地存在（要一起上传）。

用法：
  python3 -I scripts/verify-appcast.py <appcast.xml> <附件目录> <本次版本> <owner/repo> [--fix]
  --fix  先把每个条目的地址改回各自的 tag 目录（就地写回），再校验。
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
NS = {"sparkle": SPARKLE}
URL_RE = re.compile(r"^https://github\.com/(?P<repo>[^/]+/[^/]+)/releases/download/(?P<tag>[^/]+)/(?P<name>[^/]+)$")


def fix_urls(path, repo):
    """逐个 <item> 把 enclosure url 的 tag 段改成该条目自己的版本号。保持原文其余部分不动。"""
    text = open(path, encoding="utf-8").read()
    out, pos = [], 0
    for m in re.finditer(r"<item>.*?</item>", text, flags=re.S):
        block = m.group(0)
        ver = re.search(r"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>", block)
        if ver:
            tag = "v" + ver.group(1).strip()
            block = re.sub(
                r'url="https://github\.com/[^/"]+/[^/"]+/releases/download/[^/"]+/',
                f'url="https://github.com/{repo}/releases/download/{tag}/',
                block,
            )
        out.append(text[pos:m.start()])
        out.append(block)
        pos = m.end()
    out.append(text[pos:])
    new = "".join(out)
    if new != text:
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(new)
        os.replace(tmp, path)


def verify(path, directory, version, repo):
    problems = []
    root = ET.parse(path).getroot()
    items = root.findall("./channel/item")
    found_current = False
    for item in items:
        ver = (item.findtext("sparkle:shortVersionString", namespaces=NS) or "").strip()
        if not ver:
            problems.append("有条目缺少 sparkle:shortVersionString")
            continue
        tag = "v" + ver
        enclosures = item.findall("enclosure") + item.findall("sparkle:deltas/enclosure", NS)
        main = item.find("enclosure")
        if main is None:
            problems.append(f"{ver}: 缺少主 enclosure")
        is_current = ver == version
        found_current |= is_current
        for enc in enclosures:
            url = enc.get("url", "")
            m = URL_RE.match(url)
            if not m:
                problems.append(f"{ver}: 地址格式不对：{url}")
                continue
            if m.group("repo") != repo:
                problems.append(f"{ver}: 地址不在仓库 {repo}：{url}")
            if m.group("tag") != tag:
                problems.append(f"{ver}: 地址指向了别的版本 {m.group('tag')}（应为 {tag}）：{url}")
            local = os.path.join(directory, m.group("name"))
            length = enc.get("length")
            if os.path.exists(local):
                size = os.path.getsize(local)
                if str(size) != str(length):
                    problems.append(f"{ver}: {m.group('name')} length={length} 与本地文件 {size} 字节不一致")
            elif is_current:
                problems.append(f"{ver}: 本次版本引用的 {m.group('name')} 不在 {directory}（漏传会让升级失败）")
    if not found_current:
        problems.append(f"appcast 里没有本次版本 {version} 的条目")
    return problems


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 4:
        print(__doc__)
        return 2
    path, directory, version, repo = args
    if "--fix" in argv:
        fix_urls(path, repo)
    problems = verify(path, directory, version, repo)
    if problems:
        print("✗ appcast 校验失败：")
        for p in problems:
            print("   - " + p)
        return 1
    print(f"✓ appcast 校验通过（本次 {version}，各条目地址均指向自己的 tag）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
