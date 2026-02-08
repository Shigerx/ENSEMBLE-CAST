# Theater UI — 設計書

> ENSEMBLE CAST の開発をブラウザで「映画鑑賞」する Web UI
> 「え？これ無料？」レベルのクオリティを目指す

---

## コンセプト

「映画館で AI キャラクターの開発を鑑賞する」

ダッシュボードではない。映画体験。
暗い劇場に座り、スクリーンに映し出される開発の様子を眺める。
キャラクターのセリフは字幕として流れ、コードの変更はブランチツリーとして映像になる。

---

## アーキテクチャ

```
[ENSEMBLE-CAST ファイルシステム]        [Theater Server]           [ブラウザ]
                                         Python stdlib
  logs/activity.log ──┐                  ~100行, <20MB RAM
  queue/tasks/*.yaml ──┤
  cast/roster.yaml   ──┼── read ──→  GET /api/activity  ──→  fetch (3s poll)
  logs/*_status.txt  ──┤             GET /api/cast       ──→  fetch (3s poll)
  dashboard.md       ──┤             GET /api/tasks      ──→  fetch (3s poll)
  config/production  ──┘             GET /api/events     ──→  SSE (realtime)
                                     GET /               ──→  theater.html
```

### 技術選定

| 層 | 技術 | 理由 |
|----|------|------|
| サーバー | Python stdlib (`http.server` + `json`) | WSL に既存。pip 不要。最軽量 |
| フロント | 単一 HTML ファイル | npm/ビルド不要。ゼロ依存 |
| スタイル | Tailwind CSS (CDN) | ユーティリティベース。CDN で即使用 |
| UI | Preact (CDN, ~3KB) | React 互換で超軽量 |
| リアルタイム | SSE (Server-Sent Events) | WebSocket より軽量。片方向で十分 |

### 起動コマンド

```bash
bash scripts/theater-ui.sh
# → Python サーバー起動 (port 3939)
# → ブラウザで http://localhost:3939 を自動オープン
```

---

## 画面構成

```
┌─────────────────────────────────────────────────────────────┐
│                        天井（暗い勾配）                       │
│                                                             │
│  ┌─ SCREEN ───────────────────────────────────────────────┐ │
│  │                                                         │ │
│  │  ┌─ 映像エリア: ブランチツリー + ファイル変更 ────────┐ │ │
│  │  │                                                     │ │ │
│  │  │   main ────●────●────●──────→                       │ │ │
│  │  │            ├─ giorno/17  ●━━━●━━▶                   │ │ │
│  │  │            ├─ narancia/18  ●━━●━▶                   │ │ │
│  │  │            ├─ mista/19  ●━━━●━━▶                    │ │ │
│  │  │            └─ bucciarati/20  ○ (waiting)            │ │ │
│  │  │                                                     │ │ │
│  │  │   [+2 files] src/components/research/ResearchForm.. │ │ │
│  │  │   [+1 file]  src/lib/r2.ts                         │ │ │
│  │  │                                                     │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  │                                                         │ │
│  │  ┌─ 字幕エリア ────────────────────────────────────────┐ │ │
│  │  │  🌟 ジョルノ                                         │ │ │
│  │  │  「無駄無駄無駄ッ！リサーチフォーム…命を吹き込みますよ」│ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────┘ │
│                       〰️ 光漏れ 〰️                            │
│                                                             │
│  ┌─ フィルムストリップ（Phase タイムライン）─────────────────┐ │
│  │ ◀ [Scene 3 ✅] [Scene 4 ▶ 上映中] [Scene 5 ⏳] ▶       │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌─ 座席パネル（キャスト状態）─────────────────────────────┐ │
│  │ [🌟 ジョルノ 🟢]  [⚡ ナランチャ 🟢]  [🔫 ミスタ 🟢]  │ │
│  │  FEリード #17     UI #18             インフラ #19       │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                             │
│  ─── 🍿 客席 ──────────────────────────────────────────────│
│  > Producer に話しかける...                     [送信]      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## エリア詳細

### 1. スクリーン — 映像エリア（メイン）

開発の「映像」を映す。映画の本編に相当。

#### ブランチツリー（常時表示）
- main ブランチを水平ラインで表示
- 各 Cast のブランチが分岐して伸びる
- コミットはノード（●）として表示
- 進行中のブランチはアニメーションで脈動
- `depends_on` の依存関係を点線で表示
- Cast ごとにキャラカラーで色分け

#### ファイル変更フィード（コミット時に表示）
- 新しいコミットが入ったらブランチツリーの下にフェードイン
- `[+2 files] src/components/...` のように簡潔に
- 数秒で自動フェードアウト

#### 能力発動演出
- `ability` イベント検知時、該当キャラのブランチが光る
- CSS アニメーション: glow + pulse + 能力名テキスト表示
- 例: ジョルノのブランチが金色に光り「ゴールド・エクスペリエンス」表示

### 2. スクリーン — 字幕エリア

映画の字幕。キャラクターのセリフ。

- activity.log の `chat` / `progress` / `ability` イベントを表示
- SSE でリアルタイム受信
- 新しい字幕はフェードインで出現
- 古い字幕はフェードアウトで消える
- 同時に表示するのは最新 2-3 件
- キャラ名 + emoji をプレフィックスに
- キャラカラーで色付け

### 3. フィルムストリップ（Phase タイムライン）

映画のシーン（コンテ）を横に並べる。

```
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ Scene 1  │  │ Scene 2  │  │ Scene 3  │  │ Scene 4  │
│ 初期構築  │  │ API基盤  │  │ Gemini   │  │ UI+統合   │
│ ✅ 完了  │→│ ✅ 完了  │→│ ✅ 完了  │→│ ▶ 上映中  │
│ ━━━━━━━━ │  │ ━━━━━━━━ │  │ ━━━━━━━━ │  │ ━━━━▶    │
│ 3/3 done │  │ 4/4 done │  │ 3/3 done │  │ 1/4 done │
└──────────┘  └──────────┘  └──────────┘  └──────────┘
```

- 横スクロール可能
- 現在上映中の Scene がハイライト
- 完了 Scene はフィルムっぽいセピア調
- 未開始 Scene は暗い

### 4. 座席パネル（キャスト状態）

キャスト全員の状態を一覧。映画館の座席表のイメージ。

- キャラ emoji + 名前 + 状態インジケータ
- 🟢 処理中 / 🟡 完了待機 / 🔴 blocked / 🔵 起動中 / ⬜ 待機
- 担当タスク ID + タイトル
- hover でタスク詳細をポップアップ

### 5. 客席（Owner 入力エリア）

- テキスト入力欄
- 送信 → Python サーバー → Producer の tmux ペインに send-keys
- 送信成功/失敗のフィードバック
- 過去の送信履歴を薄く表示

---

## ビジュアルデザイン

### カラーパレット

```
背景（天井〜壁）:  #0a0a0f → #12121a  (深いダークグラデーション)
スクリーン背景:    #1a1a2e             (少し明るいダーク)
スクリーン枠:      #2a2a3e             (縁取り)
光漏れ:            rgba(255,200,100,0.05)  (暖かい金色)
字幕テキスト:      #ffffff             (白、影付き)
フィルムストリップ: #1e1e28             (暗めパネル)
客席:              #0f0f18             (最も暗い)
アクセント:        #f0c040             (金 = ゴールド・エクスペリエンス)
```

### キャラカラー

| Cast | カラー | 由来 |
|------|--------|------|
| giorno | #f0c040 (金) | ゴールド・エクスペリエンス |
| bucciarati | #4a9eff (青) | スティッキィ・フィンガーズの青 |
| narancia | #ff6b35 (橙) | エアロスミスの暖色 |
| mista | #8b5cf6 (紫) | セックス・ピストルズ |
| abbacchio | #6b7280 (灰) | ムーディー・ブルースの渋さ |

### 演出効果（CSS only）

| トリガー | 演出 |
|---------|------|
| 新しい字幕 | フェードイン + 下からスライド |
| コミット追加 | ブランチにノード追加アニメーション |
| ability イベント | キャラカラーの glow + pulse |
| タスク完了 | ブランチが main にマージするアニメーション |
| Phase 完了 | フィルムストリップの Scene が完了色に変化 |
| blocked | 赤い点滅 |

---

## API 仕様

### GET /api/activity?limit=50

activity.log の最新 N 行を JSON で返す。

```json
{
  "entries": [
    {
      "timestamp": "2026-02-08T13:45:00",
      "actor": "giorno",
      "event": "chat",
      "message": "無駄無駄無駄ッ！リサーチフォーム着手"
    }
  ]
}
```

### GET /api/cast

roster.yaml + status.txt + persona.yaml を統合。

```json
{
  "cast": [
    {
      "slug": "giorno",
      "character_name": "ジョルノ・ジョバァーナ",
      "emoji": "🌟",
      "dev_role": "フロントエンドリード",
      "color": "#f0c040",
      "ability_name": "ゴールド・エクスペリエンス",
      "state": "処理中",
      "task_id": 17,
      "task_title": "リサーチ投稿ページ フォームUI"
    }
  ]
}
```

### GET /api/tasks

queue/tasks/*.yaml を統合。

```json
{
  "tasks": [
    {
      "id": 17,
      "title": "リサーチ投稿ページ フォームUI",
      "slug": "giorno",
      "status": "in_progress",
      "branch": "cast/giorno/17-research-form",
      "worktree": "/tmp/giorno-17",
      "depends_on": [],
      "progress": 50
    }
  ]
}
```

### GET /api/worktrees

git worktree list の結果。

```json
{
  "target_path": "/mnt/c/Users/shige/antigravity/flare",
  "worktrees": [
    {
      "path": "/mnt/c/Users/shige/antigravity/flare",
      "branch": "main",
      "changes": 0
    },
    {
      "path": "/tmp/giorno-17",
      "branch": "cast/giorno/17-research-form",
      "slug": "giorno",
      "changes": 3
    }
  ]
}
```

### GET /api/phases

dashboard.md をパースして Phase 情報を返す。

```json
{
  "current_phase": 4,
  "phases": [
    { "number": 1, "title": "初期構築", "status": "complete", "tasks_done": 3, "tasks_total": 3 },
    { "number": 4, "title": "UI+API統合", "status": "active", "tasks_done": 0, "tasks_total": 4 }
  ]
}
```

### GET /api/events (SSE)

activity.log を tail -f して新しい行をリアルタイムに push。

```
event: activity
data: {"timestamp":"2026-02-08T13:45:00","actor":"giorno","event":"chat","message":"..."}

event: activity
data: {"timestamp":"2026-02-08T13:45:30","actor":"narancia","event":"progress","message":"..."}
```

### POST /api/message

Owner → Producer へのメッセージ送信。

```json
// Request
{ "message": "Phase 4 の進捗を教えて" }

// Response
{ "success": true }
```

---

## ファイル構成

```
scripts/
  theater-ui.sh          # 起動スクリプト（サーバー起動 + ブラウザオープン）
  theater-server.py      # Python サーバー（API + 静的ファイル配信）
ui/
  theater.html           # 単一 HTML ファイル（Preact + Tailwind CDN）
```

## 起動フロー

```bash
# theater-ui.sh の処理:
1. python3 scripts/theater-server.py &  (バックグラウンド起動)
2. ポートが開くまで待機 (max 5秒)
3. xdg-open http://localhost:3939 || open http://localhost:3939
4. echo "Theater UI: http://localhost:3939"
5. echo "停止: Ctrl+C"
6. wait  (サーバープロセスを待つ)
```

---

## 優先度

### MVP（最初のリリース）
- [ ] Python サーバー（activity, cast, tasks API）
- [ ] 映画館背景 + スクリーン枠
- [ ] 字幕表示（SSE リアルタイム）
- [ ] キャスト状態パネル
- [ ] タスク進捗表示

### v1.1
- [ ] ブランチツリー描画（SVG）
- [ ] フィルムストリップ（Phase タイムライン）
- [ ] 能力発動アニメーション
- [ ] Owner 入力エリア

### v1.2
- [ ] コミットノード追加アニメーション
- [ ] マージアニメーション
- [ ] ファイル変更フィード
- [ ] レスポンシブ対応（スマホ鑑賞）

---

## 備考

- メモリ予算: < 20MB（Python サーバー 1 プロセス）
- ポート: 3939（語呂: サンキュー・サンキュー）
- ターミナル版 show-live.sh は残す（SSH 環境用フォールバック）
- production.yaml のキャラ情報からカラーを自動マッピング
- 将来的に persona.yaml にカラーコード追加して完全カスタム化
