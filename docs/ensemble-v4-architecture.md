# ENSEMBLE-CAST v4 アーキテクチャ設計書

> **ステータス**: 設計合意完了。未実装。
> **合意日**: 2026-02-09
> **ディベートログ**: [ensemble-v4-debate-log.md](ensemble-v4-debate-log.md)（Polnareff vs Fugo、3ラウンド、全11項目100%合意）
> **関連設計**: [swarm-v2-design.md](swarm-v2-design.md) | [p25-debate-log.md](p25-debate-log.md)

---

## 1. 背景と動機

2つのX投稿が設計議論のきっかけ:
- **篠塚モデル**: Agent Teams で11体AIチーム。Red Team が直接フィードバック
- **Carliniモデル**: 16体 Claude Code 並列。Git協調、オーケストレーター不要

### 現状の課題

1. **Director がボトルネック**: Cast間の全通信がDirector経由の伝言ゲーム
2. **並列化の旨味が出ていない**: 各Castは指示待ち。議論・調整不可
3. **Red Team / Review が常設でない**: 独立した批判的視点がない
4. **チームが学習しない**: 個人記録のみ。チームノウハウ蓄積なし
5. **CI/CD がない**: テスト自動検証なし
6. **Context Window 汚染**: テスト出力がコンテキストに流れ込む

### 核心の設計判断

> ディベートで最大の論点だった通信レイヤーは **ファイルベース + send-keys** に決定。
> Agent Teams（TeamCreate/SendMessage）は tmux の独立プロセスCastとは共存不可能と判明。
> Agent Teams は P7 オプションとして将来検討。詳細: [debate-log Round 1〜2](ensemble-v4-debate-log.md#1-アーキテクチャの問題点-agent-teams-とtmux-cast-は共存不可能)

---

## 2. アーキテクチャ概要

```
Owner/Producer（人間）
  ↓ tmux ペインで直接対話
Director（テックリード: タスクプール設計 + マージ判断 + Design Debate 主催）
  ↓ queue/task_pool.yaml にタスク投入
  ↓ queue/tasks/<slug>.yaml で配布 or Cast自律取得
┌──────────────────────────────────────────────────────────┐
│  Cast間通信: queue/discussion/<topic>.yaml               │
│  + send-keys で相手を起床                                │
│  + 全メッセージが Director にも可視                       │
│  + 4ルール: 聞くOK/変えるNG, 短く, 全記録, 往復2回まで   │
│                                                          │
│  giorno(FE) ←→ bucciarati(BE) ←→ narancia(UI) ←→ mista │
│                                                          │
│  abbacchio（Red Team）                                   │
│    → 全ブランチ git diff 閲覧                            │
│    → Cast に直接 send-keys で指摘                        │
│    → CI 結果に基づくマージブロック権                      │
│    → 提案のみ。命令権なし                                │
└──────────────────────────────────────────────────────────┘
  ↓ git push per branch
CI (Node.js: scripts/stage-manager/ci.js)
  → build + test（段階的: level 1〜4）
  → 結果を queue/ci_results/<branch>.yaml（5行サマリー）
  → 全ログは logs/ci/<branch>.log
  → 失敗なら Cast を send-keys で起床
```

### Director の役割変更

| v3 | v4 |
|----|-----|
| 全通信ハブ（Cast間の伝言ゲーム） | テックリード（タスクプール設計 + マージ判断） |
| Cast への個別タスク配布 | タスクプールに投入。Cast が自律取得 |
| 全レビュー実施 | Red Team（abbacchio）に委譲。マージ判断のみ |
| 設計判断を1人で行う | Design Debate Protocol で Advocate/Challenger を召喚 |

---

## 3. Phase 計画

| Phase | 内容 | 成果物 | 期間 |
|-------|------|--------|------|
| **P1** | Context汚染対策 + chronicle handoff | cast_template.md 更新, chronicle.yaml 仕様変更 | 1日 |
| **P2** | CI基盤 | ci.js, post-commit hook, config/ci.yaml, ログ分離 | 1-2日 |
| **P2.5** | Design Debate Protocol | director.md 更新, queue/design/ | 半日 |
| **P3** | Cast間通信基盤 | queue/discussion/ 仕様, CLAUDE.md 4ルール追加 | 1-2日 |
| **P4** | Red Team昇格 | instructions/red_team.md, abbacchio権限変更 | 1日 |
| **P5** | Director薄体化 | task_pool.yaml, Cast自律取得フロー, director.md 大幅改訂 | 2日 |
| **P6** | Team Memory | memory/team_knowledge/, distill-phase.sh | 1-2日 |
| **P7** | Agent Teams統合（オプション） | Director=TeamLeader構造, ペルソナ永続化 | GA後に評価 |

**合計: P1〜P6 で 7〜10日。P7 は未定。**

> P3 を P4 より前に置いた理由: abbacchio が Cast に直接指摘する仕組み自体が Cast間通信基盤の上に成り立つ。
> 詳細: [debate-log Round 2](ensemble-v4-debate-log.md#2-phase-計画の修正)

---

## 4. 仕様一覧

### 4.1 Cast間通信 — queue/discussion/

```yaml
# queue/discussion/<topic-slug>.yaml
topic: "リサーチAPIのレスポンス型"
started_by: giorno
started_at: "2026-02-10T14:00:00"
status: open  # open | resolved | escalated

messages:
  - from: giorno
    to: bucciarati
    content: "GET /research/:id のレスポンスに tags フィールド足せる？型定義見たい"
    timestamp: "2026-02-10T14:00:00"

  - from: bucciarati
    to: giorno
    content: "OK。src/types/research.ts の ResearchResult 型を見て。tags: string[] で追加する"
    timestamp: "2026-02-10T14:05:00"

# 往復2回（4メッセージ）でresolvedにならない場合:
# status: escalated + Directorにsend-keys
```

**4つのルール**（CLAUDE.md に追記）:

1. **聞くのはOK、変えるのはNG** — 情報取得は自由。相手のタスク変更・設計判断はDirector経由
2. **短く、ファイル参照** — メッセージは200文字以内。長い情報はファイルパスを記載
3. **全記録** — 全メッセージは queue/discussion/ に保存。Directorはいつでも閲覧可能
4. **往復2回まで** — 1トピック最大4メッセージ。3往復目が必要なら status: escalated にしてDirectorへ

> ルール簡素化の経緯: [debate-log Round 2](ensemble-v4-debate-log.md#3-cast間通信ルール-採用--簡素化)

---

### 4.2 chronicle.yaml handoff セクション

```yaml
# cast/members/<slug>/chronicle.yaml

# === Section 1: Handoff（次の自分への引き継ぎ）===
# コンパクション/再起動時に最初に読むセクション
# 毎タスク完了時 + セッション終了時に更新必須
handoff:
  current_task:
    id: 3
    title: "リサーチAPI CRUD実装"
    status: in_progress  # assigned | in_progress | done | blocked
    branch: "cast/bucciarati/3-research-api"
    worktree: "/tmp/bucciarati-3"
  done_in_this_session:
    - "POST /api/research endpoint 完成"
    - "D1 テーブル research_items 作成済み"
    - "Zod バリデーション追加"
  next_steps:
    - "GET /api/research/:id を実装"
    - "DELETE /api/research/:id を実装"
    - "エラーハンドリング追加（404, 500）"
  blockers: []
  files_i_own:
    - "src/api/routes/research.ts"
    - "src/db/schema.sql"
  context_notes: |
    Hono の app.route() でプレフィックス管理。
    D1 binding 名は "DB"（wrangler.toml で確認済み）。
  updated_at: "2026-02-10T15:30:00"

# === Section 2: Entries（累積記録）===
# 従来の chronicle。Phase 蒸留の入力データにもなる
entries:
  - id: 1
    task_id: 1
    action: "プロジェクト初期化（Astro + Tailwind + shadcn）"
    files_changed: ["package.json", "astro.config.mjs", "tailwind.config.ts"]
    result: "ビルド成功確認"
    mood: "覚悟はできている"
    timestamp: "2026-02-09T10:00:00"
```

> progress.yaml 新設を取りやめ、chronicle.yaml 拡張に決定した経緯: [debate-log Position B 5-C](ensemble-v4-debate-log.md#5-c-復帰フローの一貫性)

---

### 4.3 CI — scripts/stage-manager/ci.js

```
トリガー: .githooks/post-commit から呼び出し
入力:   直近のコミットのブランチ名
出力:   queue/ci_results/<branch-slug>.yaml + logs/ci/<branch-slug>.log
設定:   config/ci.yaml
```

**段階的テストレベル**（Director がプロジェクト成熟度に応じて変更）:

| Level | 実行内容 | 適用時期 |
|-------|---------|---------|
| 1 | build のみ | Phase初期 |
| 2 | build + typecheck | 型定義安定後 |
| 3 | build + typecheck + unit test | API実装後 |
| 4 | build + typecheck + unit + e2e | UI結合後 |

**ci_results YAML フォーマット**:

```yaml
branch: "cast/giorno/5-search-ui"
commit: "abc1234"
timestamp: "2026-02-10T16:00:00"
level: 2
results:
  build: { status: "pass", duration_ms: 3200 }
  typecheck: { status: "fail", summary: "src/App.tsx(42): TS2322 type mismatch" }
overall: "fail"
log_path: "logs/ci/cast-giorno-5-search-ui.log"
```

**失敗時の通知**: ci.js → 結果YAML出力 → notify-ci.sh → wake-agent.sh で関係者を起床

**実装時の注意**:
- worktree 対応が必要（`git rev-parse --show-toplevel` でパス取得）
- 通知は ci.js から分離して notify-ci.sh に（スコープ肥大化防止）

> テスト戦略の段階化: [debate-log Position B 5-D](ensemble-v4-debate-log.md#5-d-テスト戦略の欠如)

---

### 4.4 Red Team — abbacchio 昇格

**ロール**: 独立した批判的レビュアー。コードを書かず、全Castの成果物を検証する。

**権限**:
- 全Cast のブランチを `git diff main...<branch>` で閲覧
- 任意の Cast に queue/discussion/ 経由で直接指摘
- CI 結果（queue/ci_results/）を閲覧
- dashboard.md の「Red Team Findings」セクションに直接記入
- Director に「このマージをブロックすべき」と報告（マージブロック権）

**禁止**:
- 自分でコードを書かない（F001）
- タスクの配布・変更をしない（F002）
- Cast に修正を命令しない。提案のみ（F003）
- Owner に直接報告しない。Director 経由（F004）

**レビュー観点**: BUILD, TYPES, SPEC, SECURITY, ASSUMPTIONS, REGRESSION, INTEGRATION

**トリガー**:
- Cast がタスク完了報告 → Director が send-keys で起床
- Director が Phase 中間で俯瞰レビューを依頼
- CI が失敗 → notify-ci.sh が send-keys で起床

**報告フォーマット**: queue/reports/abbacchio_report.yaml
- verdict: approved | blocked | conditional
- conditional の場合は must_fix リスト付き

**マージフロー**: Red Team レビュー → Director がマージ実行（二段階）

> マージ権限をDirector維持にした理由: [debate-log Position B 5-B](ensemble-v4-debate-log.md#5-b-マージフロー)

---

### 4.5 Design Debate Protocol

> **P2.5 再設計ディベートで詳細化済み**: [p25-debate-log.md](p25-debate-log.md)（全14項目100%合意）

**メンバー**:
- **Advocate**（擁護者）: 設計を擁護。必須
- **Challenger**（批判者）: 設計を攻撃。必須
- **Consultant**（専門顧問）: 技術的見解。オプション。v3 Technical Advisor と同一概念

**基盤**: Task tool 逐次方式（Agent Teams は不使用。v4合意: AT = P7オプション）

**ファイル構成**:
```
queue/design/
  <phase>_debate.md        # 議論本体（セクション A1, C1, T1, A2, C2）
  <phase>_final.yaml       # 最終合意（構造化 YAML）
  adhoc_<topic>_debate.md  # アドホック議論（Phase途中）
  adhoc_<topic>_final.yaml
```

**実行フロー（最大2ラウンド・対称構造）**:

```
Round 1:
  1. Director が _debate.md 作成
  2. Task tool → Advocate（出力: Section A1）
  3. Task tool → Challenger（出力: Section C1）
  4. Task tool → Consultant（出力: Section T1）← オプション

Director 判断: 合意済み → _final.yaml / 重大反論あり → Round 2

Round 2（Consultant は参加しない）:
  5. Task tool → Advocate（出力: Section A2）
  6. Task tool → Challenger（出力: Section C2）

Director が統合 → _final.yaml
```

**アドホック Debate**（Phase途中）:
- 対象 Cast を一時停止 → Round 1 のみ → Consultant なし → 完了後 Cast 起床

**スキップ条件**: タスク数2以下、バグ修正のみ、Owner許可。スキップ時は dashboard.md に理由を記載

**_final.yaml フォーマット**:
```yaml
phase: 3
debate_date: "2026-02-10"
rounds: 1
consultant_called: true
consultant_theme: "バックエンド API 設計"
participants: ["advocate", "challenger", "consultant"]

agreed:
  - point: "Hono + D1 でバックエンド構築"
    rationale: "Cloudflare 完結の要件に合致"

unresolved:
  - point: "KV vs D1 のキャッシュ戦略"
    escalated_to: "dashboard.md 🚨要対応"

tasks_adjusted:
  - task_id: 5
    change: "データモデルに tags フィールド追加"
    reason: "Challenger の指摘により"
```

---

## 5. コストモデル

**前提**: Max プラン（$300/月）。トークン課金ではないため Haiku はコスト削減にならない。

| ロール | モデル | 理由 |
|--------|--------|------|
| Director | Sonnet (default) | タスク設計・アーキ判断 |
| Cast (実装) | Sonnet (default) | コード品質が必要 |
| Red Team | Sonnet (default) | 批判的思考が必要 |
| 蒸留・分類 | Haiku (Task tool) | **速度向上**。定型作業のみ |
| CI / health | Node.js (非LLM) | 判断不要な検証にLLM不要 |

**レートリミット対策**:
- 7プロセス同時稼働 → イベント駆動厳守（全員が同時に動かないように）
- Cast間通信はファイルベース → API 呼び出しを最小化
- CI は非LLM → API 消費ゼロ

> Haiku のコスト意味の修正経緯: [debate-log Position B 3](ensemble-v4-debate-log.md#3-コスト見積りの妥当性)

---

## 6. 変更ファイル一覧（Phase別）

### P1: Context汚染対策 + chronicle handoff

| ファイル | 変更内容 |
|---------|---------|
| `instructions/cast_template.md` | セルフチェック出力リダイレクト手順。chronicle handoff 更新手順 |
| `CLAUDE.md` | セクション追加「Context Window 汚染防止ルール」 |
| `cast/members/*/chronicle.yaml` | handoff セクション仕様追加 |

### P2: CI基盤

| ファイル | 変更内容 |
|---------|---------|
| `scripts/stage-manager/ci.js` | 新規。自動テスト実行エンジン |
| `config/ci.yaml` | 新規。CI レベル設定 |
| `.githooks/post-commit` | 新規。ci.js トリガー |
| `queue/ci_results/` | 新規ディレクトリ |
| `logs/ci/` | 新規ディレクトリ |
| `instructions/cast_template.md` | CI結果の読み方・対応方法を追加 |
| `.gitignore` | queue/ci_results/, logs/ci/ を追加 |

### P2.5: Design Debate Protocol

> 詳細: [p25-debate-log.md](p25-debate-log.md)

| ファイル | 変更内容 |
|---------|---------|
| `queue/design/` | 新規ディレクトリ |
| `instructions/director.md` | Design Debate Protocol セクション追加（トリガー/スキップ条件、実行手順、プロンプトテンプレート） |
| `CLAUDE.md` | セクション追加「Design Debate Protocol」概要 |
| `.gitignore` | queue/design/ を追加 |

### P3: Cast間通信基盤

| ファイル | 変更内容 |
|---------|---------|
| `queue/discussion/` | 新規ディレクトリ |
| `CLAUDE.md` | セクション追加「Cast間通信ルール」（4ルール） |
| `instructions/cast_template.md` | Cast間通信の手順・ルール追加 |
| `instructions/director.md` | discussion/ の監視方法、エスカレーション対応追加 |
| `scripts/send-message.sh` | Cast→Cast の send-keys 対応 |
| `.gitignore` | queue/discussion/ を追加 |

### P4: Red Team昇格

| ファイル | 変更内容 |
|---------|---------|
| `instructions/red_team.md` | 新規。Red Team 専用指示書 |
| `instructions/reviewer.md` | 廃止 or Red Team への移行注記 |
| `CLAUDE.md` | ファイル所有権マトリクスに Red Team 追加 |
| `instructions/director.md` | Red Team 起床タイミング、マージブロック対応追加 |
| `dashboard.md テンプレート` | 「Red Team Findings」セクション追加 |

### P5: Director薄体化

| ファイル | 変更内容 |
|---------|---------|
| `queue/task_pool.yaml` | 新規。全タスクプール |
| `instructions/director.md` | 大幅改訂: 配布→プール作成、マージ/統合専任 |
| `instructions/cast_template.md` | タスク自律取得フロー追加 |
| `CLAUDE.md` | セクション追加「セルフサーブタスク管理」 |

### P6: Team Memory

| ファイル | 変更内容 |
|---------|---------|
| `memory/team_knowledge/` | 新規ディレクトリ（patterns, anti_patterns, decisions, retrospective） |
| `scripts/distill-phase.sh` | 新規。Phase 蒸留スクリプト |
| `instructions/cast_template.md` | team_knowledge/ の読み込みを startup に追加 |
| `instructions/director.md` | Phase 境界に distill-phase.sh 実行を追加 |

---

## 7. ディベートで潰した設計バグ

| 発見された問題 | 発見者 | もし実装後に発覚していたら |
|---------------|--------|--------------------------|
| Agent Teams + tmux 共存不可 | Fugo (Round 1) | Phase C 全面やり直し（2-3日） |
| テスト戦略なし CI 空回り | Fugo (Round 1) | CI導入後に気づく（1日） |
| Cast間通信カオス | Fugo (Round 1) | 通信爆発 → ルール再設計（1-2日） |
| chronicle vs progress の重複 | Fugo (Round 1) | ファイル乖離 → 復帰フロー混乱 |
| コストモデルの前提ミス | Fugo (Round 1) | Haiku最適化に無駄な時間 |

**合計: 5-7日分の手戻りを、コード0行の段階で防いだ。**

---

## メタ情報

| 項目 | 値 |
|------|-----|
| 起草日 | 2026-02-09 |
| 合意日 | 2026-02-09 |
| ディベート参加者 | Polnareff (Position A) / Fugo (Position B) — 共に Claude Opus 4.6 |
| ディベート形式 | 3ラウンド（起草 → 反論 → 合意形成） |
| 合意率 | 100%（Round 2.5 で残存差異を解消） |
| v4 ディベートログ | [ensemble-v4-debate-log.md](ensemble-v4-debate-log.md) |
| P2.5 ディベートログ | [p25-debate-log.md](p25-debate-log.md) |
| Swarm v2 設計 | [swarm-v2-design.md](swarm-v2-design.md) |
