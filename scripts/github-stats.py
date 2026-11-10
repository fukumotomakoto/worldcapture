#!/usr/bin/env python3
"""WorldCapture · GitHub 仓库数据每日存档。

为什么要有它（2026-11-10）：GitHub 的访问/克隆统计**只保留最近 14 天**，过期即永久消失。
想看推广效果的长期趋势，就得每天把它抓下来、按日期合并进累计历史。

产物（metrics/ 已 gitignore，不入库）：
  metrics/github/snapshots/YYYY-MM-DD.json   当天全量快照
  metrics/github/traffic.json                累计的每日 views/clones（跨 14 天窗口合并）
  metrics/github/latest.json                 上一次快照（用来比对「有没有新动静」）

有新动静（Star/Fork/Watch、新 Issue/PR/评论/Discussion、下载数增长）→ 桌面精灵顶气泡
（铁律：整机唯一前脸 = 精灵，本脚本不自建任何界面）。没动静不响。

用法：
  python3 scripts/github-stats.py              # 抓取 + 存档 + 有动静才提醒
  python3 scripts/github-stats.py --no-notify  # 只存档不提醒
鉴权：复用 gh CLI 已登录的账号（traffic 接口需要仓库 push 权限）。
"""
import datetime as dt
import json
import pathlib
import subprocess
import sys

REPO = "fukumotomakoto/worldcapture"
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "metrics" / "github"
SPRITE = pathlib.Path.home() / "Projects" / "desktop-sprite" / "bin" / "sprite-state"


def gh(path, paginate=False):
    cmd = ["gh", "api", "-H", "Accept: application/vnd.github+json", path]
    if paginate:
        cmd.insert(2, "--paginate")
        cmd += ["--jq", ".[]"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    if paginate:
        return [json.loads(line) for line in out.splitlines() if line.strip()]
    return json.loads(out)


def gql_discussions():
    owner, name = REPO.split("/")
    q = ('query{repository(owner:"%s",name:"%s"){discussions{totalCount}}}' % (owner, name))
    out = subprocess.run(["gh", "api", "graphql", "-f", f"query={q}"],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)["data"]["repository"]["discussions"]["totalCount"]


def snapshot():
    repo = gh(f"repos/{REPO}")
    releases = gh(f"repos/{REPO}/releases?per_page=100")
    issues = gh(f"repos/{REPO}/issues?state=all&per_page=100", paginate=True)
    comments = gh(f"repos/{REPO}/issues/comments?per_page=100", paginate=True)
    downloads = {a["name"]: a["download_count"] for r in releases for a in r["assets"]}
    return {
        "taken_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "stars": repo["stargazers_count"],
        "watchers": repo["subscribers_count"],
        "forks": repo["forks_count"],
        "issues": sum(1 for i in issues if "pull_request" not in i),
        "pulls": sum(1 for i in issues if "pull_request" in i),
        "comments": len(comments),
        "discussions": gql_discussions(),
        "downloads": downloads,
        "downloads_total": sum(downloads.values()),
        "dmg_downloads_total": sum(v for k, v in downloads.items() if k.endswith(".dmg")),
        "views_14d": gh(f"repos/{REPO}/traffic/views"),
        "clones_14d": gh(f"repos/{REPO}/traffic/clones"),
        "referrers_14d": gh(f"repos/{REPO}/traffic/popular/referrers"),
        "paths_14d": gh(f"repos/{REPO}/traffic/popular/paths"),
        "issue_titles": [f"#{i['number']} {i['title']}" for i in issues],
    }


def merge_traffic(snap):
    """把 14 天窗口里的每日数据并进累计历史（同一天以最新抓取为准）。"""
    path = OUT / "traffic.json"
    hist = json.loads(path.read_text()) if path.exists() else {"views": {}, "clones": {}}
    for kind, key in (("views", "views_14d"), ("clones", "clones_14d")):
        for day in snap[key].get(kind, []):
            hist[kind][day["timestamp"][:10]] = {"count": day["count"], "uniques": day["uniques"]}
    path.write_text(json.dumps(hist, ensure_ascii=False, indent=1, sort_keys=True))
    return hist


def changes(prev, cur):
    if prev is None:
        return []
    out = []
    for key, label in (("stars", "⭐ Star"), ("forks", "Fork"), ("watchers", "Watch"),
                       ("issues", "新 Issue"), ("pulls", "新 PR"), ("comments", "新评论"),
                       ("discussions", "新讨论"), ("dmg_downloads_total", "DMG 下载")):
        d = cur[key] - prev.get(key, 0)
        if d > 0:
            out.append(f"{label} +{d}")
    return out


def main():
    notify = "--no-notify" not in sys.argv
    (OUT / "snapshots").mkdir(parents=True, exist_ok=True)
    latest = OUT / "latest.json"
    prev = json.loads(latest.read_text()) if latest.exists() else None

    snap = snapshot()
    hist = merge_traffic(snap)
    today = dt.date.today().isoformat()
    body = json.dumps(snap, ensure_ascii=False, indent=1)
    (OUT / "snapshots" / f"{today}.json").write_text(body)
    latest.write_text(body)

    diff = changes(prev, snap)
    views_all = sum(v["count"] for v in hist["views"].values())
    print(f"[{snap['taken_at']}] ⭐{snap['stars']} fork{snap['forks']} issue{snap['issues']} "
          f"评论{snap['comments']} DMG下载{snap['dmg_downloads_total']} "
          f"访问(14天){snap['views_14d'].get('count', 0)} 访问(累计){views_all} "
          f"动静: {'、'.join(diff) or '无'}")

    if diff and notify and SPRITE.exists():
        subprocess.run([str(SPRITE), "talking", "师弟，WorldCapture 有新动静：" + "、".join(diff)],
                       capture_output=True)


if __name__ == "__main__":
    main()
