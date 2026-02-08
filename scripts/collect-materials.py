#!/usr/bin/env python3
"""
ENSEMBLE CAST - 脚本生成素材収集スクリプト

Phase完了時に脚本生成の素材を収集し、YAML形式で出力する。
stdlib のみ使用（pip不要）。

使い方:
  python3 scripts/collect-materials.py --phase 6
  python3 scripts/collect-materials.py --phase 6 --base /path/to/ENSEMBLE-CAST
  python3 scripts/collect-materials.py --phase 6 --output materials.yaml
"""

import argparse
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def yaml_escape(text: str) -> str:
    """YAML block scalar 用にテキストをエスケープする。"""
    if not text:
        return ""
    return text.rstrip("\n")


def read_file_safe(path: Path) -> str | None:
    """ファイルを読み込む。存在しない場合は None を返す。"""
    try:
        return path.read_text(encoding="utf-8")
    except (FileNotFoundError, PermissionError, OSError):
        return None


def parse_production_yaml(base: Path) -> dict:
    """production.yaml から movie title と project name を抽出する。"""
    content = read_file_safe(base / "config" / "production.yaml")
    result = {"movie_title": "", "project_name": ""}
    if not content:
        return result

    # movie.title を抽出
    m = re.search(r'movie:\s*\n\s*title:\s*"([^"]*)"', content)
    if m:
        result["movie_title"] = m.group(1)

    # project.name を抽出
    m = re.search(r'project:\s*\n\s*name:\s*"([^"]*)"', content)
    if m:
        result["project_name"] = m.group(1)

    return result


def get_cast_slugs(base: Path) -> list[str]:
    """cast/members/ 以下のディレクトリ名（slug）一覧を取得する。"""
    members_dir = base / "cast" / "members"
    if not members_dir.is_dir():
        return []
    return sorted(
        d.name for d in members_dir.iterdir()
        if d.is_dir() and not d.name.startswith(".")
    )


def extract_phase_tasks_from_dashboard(dashboard: str, phase: int) -> str:
    """dashboard.md から該当 Phase に関連する情報を抽出する。"""
    if not dashboard:
        return "(dashboard.md が見つかりません)"

    lines = dashboard.split("\n")
    relevant = []

    # Phase 情報を含む行を抽出
    # 「本日の戦果」テーブル全体を含める（Phase 番号での厳密なフィルタは難しいため全体を含む）
    in_table = False
    for line in lines:
        # プロダクション情報セクション
        if "Phase" in line and str(phase) in line:
            relevant.append(line)
        # テーブルヘッダーの検出
        if "時刻" in line and "キャスト" in line and "タスク" in line:
            in_table = True
            relevant.append(line)
            continue
        if in_table:
            if line.startswith("|"):
                relevant.append(line)
            else:
                in_table = False
        # 進捗サマリー
        if "進捗サマリー" in line or "プロダクション情報" in line:
            relevant.append(line)

    if not relevant:
        return f"(Phase {phase} に関連する情報が dashboard.md 内に見つかりません)"

    return "\n".join(relevant)


def extract_phase_from_activity_log(log_content: str, phase: int) -> str:
    """activity.log から該当 Phase 期間のイベントを抽出する。

    Phase 境界の特定:
    - phase_complete で前 Phase の終了を検出
    - 次の phase_complete で該当 Phase の終了を検出
    """
    if not log_content:
        return "(activity.log が見つかりません)"

    lines = log_content.strip().split("\n")

    # Phase 境界を検出
    phase_start_idx = 0
    phase_end_idx = len(lines)

    # phase N の開始 = phase (N-1) の phase_complete の次の行
    # phase N の終了 = phase N の phase_complete
    prev_phase_complete_idx = -1
    current_phase_complete_idx = -1

    for i, line in enumerate(lines):
        # Phase開始の検出: "Phase N" を含む task_assign, cast_start, phase2_start 等
        if f"Phase {phase}" in line and any(
            kw in line for kw in ["cast_start", "phase_complete", f"phase{phase}_start", "task_assign"]
        ):
            if "phase_complete" in line and f"Phase {phase}" in line:
                # Phase N の完了行
                current_phase_complete_idx = i
            elif current_phase_complete_idx == -1:
                # Phase N の開始に関する行（最初のものだけ使う）
                phase_start_idx = i

        # Phase N-1 の完了を検出
        if phase > 1 and f"Phase {phase - 1}" in line and "phase_complete" in line:
            prev_phase_complete_idx = i

    # 前の Phase 完了の次行から開始
    if prev_phase_complete_idx >= 0:
        phase_start_idx = prev_phase_complete_idx + 1

    # Phase N の完了行まで（見つかった場合）
    if current_phase_complete_idx >= 0:
        phase_end_idx = current_phase_complete_idx + 1

    extracted = lines[phase_start_idx:phase_end_idx]
    if not extracted:
        return f"(Phase {phase} に関連するイベントが activity.log 内に見つかりません)"

    return "\n".join(extracted)


def collect_chronicles(base: Path, slugs: list[str]) -> dict[str, str]:
    """各キャストの chronicle.yaml を読み込む。"""
    result = {}
    for slug in slugs:
        content = read_file_safe(base / "cast" / "members" / slug / "chronicle.yaml")
        if content:
            result[slug] = content
        else:
            result[slug] = f"({slug} の chronicle.yaml が見つかりません)"
    return result


def collect_reports(base: Path, slugs: list[str]) -> list[dict]:
    """各キャストの report.yaml を読み込む。"""
    result = []
    for slug in slugs:
        content = read_file_safe(base / "queue" / "reports" / f"{slug}_report.yaml")
        if content:
            result.append({"slug": slug, "report": content})
    return result


def get_git_log(base: Path, phase: int) -> str:
    """git log --oneline を取得する。Phase 期間のフィルタは簡易的に行う。"""
    try:
        proc = subprocess.run(
            ["git", "log", "--oneline", "-50"],
            cwd=str(base),
            capture_output=True,
            timeout=10,
        )
        stdout = proc.stdout.decode("utf-8", errors="replace") if proc.stdout else ""
        if proc.returncode == 0 and stdout.strip():
            return stdout.strip()
        return "(git log の取得に失敗しました)"
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return "(git コマンドが利用できません)"


def indent(text: str, spaces: int = 4) -> str:
    """テキストの各行にインデントを追加する。"""
    prefix = " " * spaces
    lines = text.split("\n")
    return "\n".join(prefix + line if line.strip() else line for line in lines)


def build_yaml_output(
    phase: int,
    production: dict,
    dashboard_summary: str,
    activity_log: str,
    chronicles: dict[str, str],
    reports: list[dict],
    git_log: str,
) -> str:
    """収集した素材をYAML形式で出力する。"""
    now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")

    parts = []
    parts.append(f"phase: {phase}")
    parts.append(f'collected_at: "{now}"')
    parts.append("production:")
    parts.append(f'  movie_title: "{production["movie_title"]}"')
    parts.append(f'  project_name: "{production["project_name"]}"')
    parts.append("")

    parts.append("dashboard_summary: |")
    parts.append(indent(yaml_escape(dashboard_summary)))
    parts.append("")

    parts.append("activity_log: |")
    parts.append(indent(yaml_escape(activity_log)))
    parts.append("")

    parts.append("cast_chronicles:")
    for slug, content in chronicles.items():
        parts.append(f"  {slug}: |")
        parts.append(indent(yaml_escape(content), 4))
    parts.append("")

    parts.append("task_reports:")
    if reports:
        for r in reports:
            parts.append(f"  - slug: {r['slug']}")
            parts.append("    report: |")
            parts.append(indent(yaml_escape(r["report"]), 6))
    else:
        parts.append("  []")
    parts.append("")

    parts.append("git_log: |")
    parts.append(indent(yaml_escape(git_log)))
    parts.append("")

    return "\n".join(parts)


def main():
    parser = argparse.ArgumentParser(
        description="ENSEMBLE CAST 脚本生成素材収集"
    )
    parser.add_argument(
        "--phase", type=int, required=True,
        help="収集対象の Phase 番号"
    )
    parser.add_argument(
        "--base", type=str, default=None,
        help="ENSEMBLE-CAST のベースパス（デフォルト: スクリプトの親ディレクトリの親）"
    )
    parser.add_argument(
        "--output", type=str, default=None,
        help="出力ファイルパス（省略時は標準出力）"
    )
    args = parser.parse_args()

    # ベースパスの決定
    if args.base:
        base = Path(args.base)
    else:
        # スクリプト自体の位置から ENSEMBLE-CAST ルートを推測
        base = Path(__file__).resolve().parent.parent

    if not base.is_dir():
        print(f"エラー: ベースパス '{base}' が見つかりません", file=sys.stderr)
        sys.exit(1)

    phase = args.phase
    print(f"[collect-materials] Phase {phase} の素材を収集中...", file=sys.stderr)

    # 1. production.yaml から作品情報を取得
    production = parse_production_yaml(base)
    print(f"  作品: {production['movie_title']} x {production['project_name']}", file=sys.stderr)

    # 2. dashboard.md からタスク情報を抽出
    dashboard_content = read_file_safe(base / "dashboard.md")
    dashboard_summary = extract_phase_tasks_from_dashboard(
        dashboard_content or "", phase
    )

    # 3. activity.log から該当 Phase のイベントを抽出
    log_content = read_file_safe(base / "logs" / "activity.log")
    activity_log = extract_phase_from_activity_log(log_content or "", phase)

    # 4. 各キャストの chronicle.yaml を収集
    slugs = get_cast_slugs(base)
    print(f"  キャスト: {', '.join(slugs)}", file=sys.stderr)
    chronicles = collect_chronicles(base, slugs)

    # 5. 各キャストの report.yaml を収集
    reports = collect_reports(base, slugs)

    # 6. git log を取得
    git_log = get_git_log(base, phase)

    # YAML 出力を組み立て
    output = build_yaml_output(
        phase=phase,
        production=production,
        dashboard_summary=dashboard_summary,
        activity_log=activity_log,
        chronicles=chronicles,
        reports=reports,
        git_log=git_log,
    )

    # 出力
    if args.output:
        output_path = Path(args.output)
        output_path.write_text(output, encoding="utf-8")
        print(f"[collect-materials] 素材を {output_path} に書き出しました", file=sys.stderr)
    else:
        # Windows コンソール（cp932等）でも Unicode を出力できるようにする
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        print(output)

    print(f"[collect-materials] 完了", file=sys.stderr)


if __name__ == "__main__":
    main()
