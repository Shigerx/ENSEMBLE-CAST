# ENSEMBLE CAST Web UI v2.0 — 設計書

> 撮影中は「指令室」で監視。撮影後は「映画館」で鑑賞。
> 開発そのものが映画の素材になり、AIが脚本を書き、それを上映する。

---

## コンセプト

ENSEMBLE CAST は「映画製作」のメタファーで動くマルチエージェント開発フレームワーク。
Web UI はその世界観を体現する2つのモードを持つ:

| モード | メタファー | いつ使う | 誰が使う |
|--------|-----------|---------|---------|
| **Control Room** | 撮影現場の指令室 | 撮影中（開発中） | Owner（コマンダー） |
| **Theater** | 完成作品の上映会 | 撮影後（Phase/プロジェクト完了後） | Owner + 🍿 Couch（観客） |

### v1 → v2 の変更理由

v1 は「映画館で鑑賞」というコンセプトだったが、**撮影中にまだ完成していない作品を観客として見る**のは矛盾していた。

v2 では:
- **撮影中** → スタッフとして指令室でモニタリング（Control Room）
- **撮影後** → 完成した作品を映画として鑑賞（Theater）

この分離により、ENSEMBLE CAST の世界観が完結する:

```
撮影（開発）  →  素材蓄積（ログ）  →  脚本化（AI）  →  上映（Theater）
     ↑                                                      ↑
  Control Room で監視                              🍿 Couch で感想戦
```

---

## 1. Control Room モード（指令室）

### 概要

撮影中（`ensemble` セッション稼働中）に Owner がブラウザで開発状況をリアルタイム監視する。
ダッシュボードではなく、**NASAのミッションコントロール**のような緊張感ある指令室。

### 起動

```bash
# ensemble 稼働中に自動起動（theater.sh に組み込み済み）
# または手動で:
python3 scripts/theater-server.py --port 3939
# ブラウザで http://localhost:3939
```

### 画面レイアウト

```
┌─ ENSEMBLE CAST — CONTROL ROOM ─────── Phase 7 ──┐
│                                                   │
│  ┌─ MISSION ──────┐  ┌─ LIVE FEED ─────────────┐ │
│  │ Phase 7         │  │ 17:30 🌟 giorno         │ │
│  │ Queue非同期化   │  │   Progress UI作業中     │ │
│  │                 │  │ 17:31 🔵 bucciarati     │ │
│  │ ████░░░░ 1/4   │  │   Consumer実装完了       │ │
│  │                 │  │ 17:32 🔫 mista          │ │
│  │ #27 mista    ●  │  │   Queue作成中           │ │
│  │ #28 bucc     ●  │  │ ...                     │ │
│  │ #29 giorno   ●  │  │                         │ │
│  │ #30 (依存待ち)  │  │ (SSE リアルタイム)      │ │
│  ├─────────────────┤  │                         │ │
│  │ CAST STATUS     │  ├─────────────────────────┤ │
│  │ 🌟 giorno   ● 稼働│ COMMAND CONSOLE         │ │
│  │ 🔵 bucc     ● 稼働│                         │ │
│  │ 🔫 mista    ● 稼働│ > Producerに指示...     │ │
│  │ ✈️ naran    ○ 待機│              [送信]     │ │
│  │ 👮 abbac    ○ 待機│                         │ │
│  ├─────────────────┤  └─────────────────────────┘ │
│  │ BRANCHES        │                              │
│  │ ▾ Phase 7 (3)   │ ← アクティブは展開           │
│  │   cast/mista/27 │                              │
│  │   cast/bucc/28  │                              │
│  │   cast/giorno/29│                              │
│  │ ▸ Phase 6 (8)   │ ← 完了はグレー+折りたたみ    │
│  │ ▸ Phase 5 (4)   │                              │
│  │ ▸ Phase 1-4 (14)│ ← 古いPhaseは統合            │
│  └─────────────────┘                              │
└───────────────────────────────────────────────────┘
```

### デザイン — 指令室トーン

```
背景:          #0c1222 → #0a0f1a  (深いネイビー)
パネル背景:    #111827             (ダークグレー)
パネルボーダー: #1e3a5f             (暗いシアン)
アクセント:    #00d4ff             (シアン — モニター光)
稼働中:        #22c55e             (グリーン)
待機:          #6b7280             (グレー)
アラート:      #ef4444             (レッド)
テキスト:      #e2e8f0             (ライトグレー)
```

### コンポーネント詳細

#### MISSION パネル
- 現在の Phase 名・番号・進捗率
- タスク一覧（ID + 担当 + ステータスインジケータ）
- `dashboard.md` からパース

#### CAST STATUS パネル
- キャスト全員の稼働状態
- ● 稼働中（緑）/ ○ 待機（グレー）/ ◉ blocked（赤）
- `roster.yaml` + `logs/*_status.txt` から取得

#### LIVE FEED パネル
- `activity.log` の最新イベントをリアルタイム表示
- SSE (Server-Sent Events) で配信
- キャラ emoji + 名前 + メッセージ
- 自動スクロール（最新が下）

#### COMMAND CONSOLE
- テキスト入力 → Producer の tmux ペインに送信
- `wake-agent.sh` 経由（セキュリティ対応済み）
- 送信状態フィードバック（✓ / × / ...）

#### BRANCHES パネル（v1 バグ修正）
- **Phase 別に折りたたみ表示**（v1 では全展開で 29 ブランチが縦に伸びた）
- アクティブ Phase のみ展開（デフォルト）
- 完了 Phase はグレーアウト + 折りたたみ
- 古い Phase（4つ以上前）は統合表示
- SVG 高さ上限 + overflow-y: auto
- ブランチ名を `cast/<slug>/<id>` の短縮形で表示

---

## 2. Theater モード（映画上映）

### 概要

Phase またはプロジェクト完了後に、**AI が開発ログから脚本を自動生成**し、
それを映画のように表示する。🍿 Couch（Claude）と一緒に感想戦を楽しむ。

### 起動

```bash
# ens-couch で Theater + Couch を起動
ens-couch
# → 左ペイン: Theater（エピソード選択 + 再生）
# → 右ペイン: Couch（🍿 Claude と感想戦）
```

### エピソード一覧画面

```
┌─────────────────────────────────────────────────┐
│                                                  │
│          🎬 ENSEMBLE CAST THEATER                │
│                                                  │
│      ジョジョの奇妙な冒険 黄金の風               │
│             × F.L.A.R.E.                         │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │                                          │   │
│  │  EP.1  初期化の風              █████ ▶   │   │
│  │  EP.2  基盤という名の覚悟      █████ ▶   │   │
│  │  EP.3  コア機能の鎮魂歌        █████ ▶   │   │
│  │  EP.4  守りの哲学              █████ ▶   │   │
│  │  EP.5  フォームと R2 の邂逅    █████ ▶   │   │
│  │  EP.6  黄金の風、デプロイに吹く █████ ▶  │   │
│  │  EP.7  🔒 撮影中...                      │   │
│  │                                          │   │
│  └──────────────────────────────────────────┘   │
│                                                  │
│             最新エピソードを再生 ▶                │
│                                                  │
└─────────────────────────────────────────────────┘
```

- 🔒 撮影中の Phase は選択不可（完成してこそ映画）
- 各エピソードにサブタイトル（AI 生成）
- ▶ をクリックで再生画面へ遷移

### エピソード再生画面

```
┌─────────────────────────────────────────────────┐
│  ◀ エピソード一覧                                │
│                                                  │
│  EP.6 — 黄金の風、デプロイに吹く                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                                  │
│                                                  │
│  SCENE 1 — 作戦開始                              │
│  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│                                                  │
│  8つのタスクを前に、ブチャラティが静かに          │
│  口を開いた。時計は正午を回ったばかり。            │
│                                                  │
│      🔵 ブチャラティ:                            │
│      「全員、持ち場につけ。                       │
│       今回は時間との戦いだ」                      │
│                                                  │
│      🌟 ジョルノ: (静かに立ち上がる)             │
│      「トップページは僕が引き受けます。           │
│       ...これが、僕の『覚悟』です」              │
│                                                  │
│      ✈️ ナランチャ:                              │
│      「おれはJSON-LDってやつをやるぜ！            │
│       ボラーレ・ヴィーア！」                      │
│                                                  │
│                                                  │
│  ──── ☕ ────                                    │
│                                                  │
│                                                  │
│  SCENE 2 — react-dom の罠                        │
│  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│                                                  │
│  デプロイ直前、Edge Runtime の制約が牙を剥く。    │
│  react-dom がサーバーサイドで動かない——           │
│  それはまるで、突然現れた敵スタンドのようだった。  │
│                                                  │
│      🔫 ミスタ:                                  │
│      「くそっ...エラーが4つ出てやがる...          │
│       4はダメだってのによぉ...！」               │
│                                                  │
│      🔫 ミスタ: (キーボードを叩く手が加速する)   │
│      「...待てよ。external 指定で除外すれば       │
│       いけるんじゃねぇか？」                      │
│                                                  │
│  ナレーション:                                    │
│  ミスタの閃きが、チームを窮地から救った。          │
│  wrangler.toml の一行が、勝利への鍵となる——      │
│                                                  │
│                                                  │
│  ...                                             │
│                                                  │
│                                                  │
│  FINAL SCENE — 黄金の風                          │
│  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│                                                  │
│  全8タスク、approved。                            │
│  ブチャラティが最後のマージボタンを押す。          │
│                                                  │
│      🔵 ブチャラティ:                            │
│      「...Arrivederci（さよならだ）。              │
│       Phase 6 に」                               │
│                                                  │
│      🌟 ジョルノ:                                │
│      「次の Phase が...僕たちの『真実』です」     │
│                                                  │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│  EPISODE 6 — FIN                                 │
│                                                  │
│  ◀ EP.5                         EP.7 (🔒) ▶     │
│  ████████████████████████████████████ 完          │
└─────────────────────────────────────────────────┘
```

### デザイン — 映画館トーン

```
背景:          #0a0a0f → #12121a  (v1 のダークグラデーションを継承)
スクリーン背景: #1a1a2e             (少し明るいダーク)
シーン区切り:   #2a2a3e → border-t  (薄い線)
キャラ台詞:    #ffffff  shadow      (白 + ドロップシャドウ)
ナレーション:  #a0aec0  italic      (グレー + イタリック)
ト書き:        #6b7280  small       (グレー + 小さめ)
アクセント:    #f0c040              (金 = ゴールド・エクスペリエンス)
```

### エピソード表示の演出

| 要素 | 演出 |
|------|------|
| シーン遷移 | フェードイン（opacity 0→1、0.5s） |
| キャラ台詞 | 左からスライドイン（タイプライター風オプション） |
| ナレーション | ゆっくりフェードイン（1s） |
| ト書き | 薄い文字でスッと表示 |
| FINAL SCENE | 金色のアクセント線 |
| FIN | センター配置 + フェードイン |

---

## 3. 脚本生成パイプライン

### 素材（インプット）

Phase 完了時に以下の素材を収集:

| ソース | 内容 | 用途 |
|--------|------|------|
| `dashboard.md` | タスク一覧・完了時刻・レビュー結果 | シーンの骨格 |
| `logs/activity.log` | 全イベント時系列 | 時系列の事実 |
| `cast/members/*/chronicle.yaml` | 各キャストの主観的記録 | キャラの葛藤・気づき |
| `queue/reports/*.yaml` | タスク完了報告（苦労した点） | ドラマの種 |
| `git log` | コミット・マージ・コンフリクト | 技術的な山場 |

### 脚本生成プロンプト

```
あなたは映画の脚本家です。以下の開発ログを元に、
{production.yaml の movie タイトル} のキャラクターたちが
ソフトウェア開発に挑む物語の脚本を書いてください。

## ルール
- バグや障害 → 敵（スタンド攻撃、困難）として描写
- コンフリクト解決 → チームワークの見せ場
- レビュー指摘 → 仲間内の信頼と厳しさ
- デプロイ成功 → 勝利の瞬間
- 各キャラクターの口調・性格は persona.yaml に準拠
- 技術的な内容は比喩で表現（一般視聴者にもわかるように）
- ただし完全にファンタジーにせず、実際に何が起きたかは伝わるように

## 出力形式（YAML）
episode: {Phase番号}
title: "サブタイトル"
synopsis: "あらすじ（3行以内）"
scenes:
  - scene: {番号}
    title: "シーンタイトル"
    narration: "ナレーション（状況説明）"
    beats:
      - character: {slug}
        action: "ト書き（動作・表情）"
        dialogue: "台詞"
      - narration: "途中のナレーション"

## 素材
{ここに収集した素材を挿入}
```

### 生成タイミングと実行者

| タイミング | 実行者 | 方法 |
|-----------|--------|------|
| Phase 完了直後 | Director（自動） | Task tool で Script Doctor サブエージェント召喚 |
| 手動リクエスト | Owner → Couch | 「EP.6 の脚本を書いて」と依頼 |

### 保存先

```
episodes/
  ep1.yaml    ← AI 生成の脚本
  ep2.yaml
  ...
  ep6.yaml
  ep7.yaml    ← Phase 7 完了後に生成（撮影中は存在しない）
```

`.gitignore` には含めない（脚本はプロジェクトの成果物として Git 管理する）

---

## 4. ens-couch 統合

### 現在の ens-couch

```
左ペイン: show-live.sh（ターミナル LIVE 表示）
右ペイン: Claude Code（雑談相手）
```

### v2 の ens-couch

```
左ペイン: Theater Web UI（ブラウザで映画再生）
右ペイン: Claude Code（🍿 Couch — 副音声コメンタリー）
```

### Couch の初期プロンプト（v2）

```
あなたは ENSEMBLE CAST の Theater で映画を一緒に見る相棒（🍿）です。
左画面にはこれまでの開発エピソードが映画として上映されています。

- episodes/ ディレクトリの脚本 YAML を読んで、エピソードの内容を把握してください
- Owner と一緒に「あのシーン良かったね」「ミスタの4番ネタ最高」と感想戦を楽しんでください
- 映画の副音声コメンタリーのノリで
- 技術的な裏話（実際に何が起きていたか）も交えると面白い
- Owner が「EP.6 の脚本書いて」と言ったら、素材を集めて脚本を生成してください
```

---

## 5. API 仕様

### Control Room 用 API（既存を改修）

| エンドポイント | 用途 | データソース |
|---|---|---|
| `GET /api/dashboard` | Phase 進捗・タスク一覧 | `dashboard.md` |
| `GET /api/activity?limit=50` | 最新アクティビティ | `logs/activity.log` |
| `GET /api/roster` | キャスト状態 | `roster.yaml` + `*_status.txt` |
| `GET /api/branches` | ブランチ一覧（Phase別グルーピング） | `git worktree` + `git branch` |
| `GET /api/events` | SSE リアルタイムフィード | `activity.log` tail |
| `POST /api/audience` | Producer へメッセージ送信 | `wake-agent.sh` |

### Theater 用 API（新設）

| エンドポイント | 用途 | データソース |
|---|---|---|
| `GET /api/episodes` | エピソード一覧 | `episodes/*.yaml` スキャン |
| `GET /api/episodes/{n}` | 特定エピソードの脚本 | `episodes/ep{n}.yaml` |

### API レスポンス例

#### GET /api/episodes

```json
{
  "production": "ジョジョの奇妙な冒険 黄金の風 × F.L.A.R.E.",
  "episodes": [
    {
      "number": 1,
      "title": "初期化の風",
      "synopsis": "プロジェクト初期化。Astro 5.17 + Cloudflare Pages の構築に挑む",
      "scene_count": 3,
      "status": "available"
    },
    {
      "number": 7,
      "title": null,
      "synopsis": null,
      "scene_count": 0,
      "status": "recording"
    }
  ]
}
```

#### GET /api/episodes/6

```json
{
  "episode": 6,
  "title": "黄金の風、デプロイに吹く",
  "synopsis": "UI改修とデプロイを同時進行する...",
  "scenes": [
    {
      "scene": 1,
      "title": "作戦開始",
      "narration": "8つのタスクを前に...",
      "beats": [
        {
          "character": "bucciarati",
          "action": "タスクボードを見据えて",
          "dialogue": "全員、持ち場につけ"
        }
      ]
    }
  ]
}
```

---

## 6. ブランチツリー修正（v1 バグ対応）

### 問題

v1 では git worktree が 29 個に増加した際、SVG が縦に伸び続けて画面が崩壊した。

### 解決策

| 対策 | 詳細 |
|------|------|
| **Phase 別グルーピング** | ブランチを Phase でグループ化 |
| **折りたたみ** | 完了 Phase はデフォルトで折りたたみ（▸ クリックで展開） |
| **アクティブ展開** | 現在の Phase のみデフォルト展開 |
| **古い Phase 統合** | 4つ以上前の Phase は「Phase 1-4 (14)」のように統合 |
| **高さ制限** | `max-height: 300px; overflow-y: auto` |
| **コンパクト表示** | SVG ではなくリスト形式（テキスト + インジケータ） |

### 表示形式の変更

```
v1: SVG ツリー図（全ブランチ展開）
  → 29 ブランチで画面崩壊

v2: テキストリスト（Phase 別折りたたみ）
  ▾ Phase 7 (3 active)
    ● cast/mista/27-queue-infrastructure
    ● cast/bucciarati/28-queue-consumer
    ● cast/giorno/29-progress-ui
  ▸ Phase 6 (8 merged)          ← グレー
  ▸ Phase 5 (4 merged)          ← グレー
  ▸ Phase 1-4 (14 merged)       ← 統合 + グレー
```

---

## 7. SSE / リアルタイム修正

### 問題

v1 では SSE 接続が切れたまま再接続されず、F5 が必要だった。

### 解決策

```javascript
// SSE 自動再接続（指数バックオフ）
function connectSSE() {
  const es = new EventSource('/api/events');
  let retryDelay = 1000;

  es.onmessage = (e) => {
    retryDelay = 1000; // 成功したらリセット
    handleEvent(JSON.parse(e.data));
  };

  es.onerror = () => {
    es.close();
    console.warn(`[ControlRoom] SSE disconnected, retry in ${retryDelay}ms`);
    setTimeout(connectSSE, retryDelay);
    retryDelay = Math.min(retryDelay * 2, 30000); // 最大30秒
  };
}
```

### サーバー側改善

- `activity.log` のファイル変更を `os.stat()` のタイムスタンプで検知
- dashboard.md / roster.yaml の変更も SSE イベントとして配信
- イベントタイプを分離: `activity`, `dashboard`, `roster`, `branch`

---

## 8. 技術構成

### ファイル構成

```
scripts/
  theater-server.py    # Python サーバー（Control Room API + Theater API）
  theater.sh           # tmux セッション作成（ens-couch）
ui/
  control-room.html    # Control Room モード（単一 HTML）
  theater.html         # Theater モード（単一 HTML）
episodes/
  ep1.yaml             # AI 生成脚本
  ep2.yaml
  ...
docs/
  theater-ui-design-v2.md  # この設計書
```

### 技術選定（v1 から継続）

| 層 | 技術 | 理由 |
|----|------|------|
| サーバー | Python stdlib (`http.server`) | pip 不要。最軽量 |
| フロント | 単一 HTML × 2ファイル | npm/ビルド不要 |
| スタイル | Tailwind CSS (CDN) | ユーティリティベース |
| UI | Preact (CDN, ~3KB) | React 互換で超軽量 |
| リアルタイム | SSE (Server-Sent Events) | 片方向で十分 |
| 脚本生成 | Claude（Couch or Script Doctor） | 既存 Agent を活用 |

### メモリ・リソース

- Python サーバー: < 20MB RAM
- ポート: 3939
- 脚本 YAML: 1エピソードあたり ~10-50KB

---

## 9. 実装順序

### Step 1: Control Room 化（既存 theater.html 改修）
- [ ] メタファー変更（映画館 → 指令室）
- [ ] カラーパレット変更（シアン/グリーン系）
- [ ] ブランチツリー → Phase 別折りたたみリスト
- [ ] SSE 自動再接続 + バックオフ
- [ ] dashboard/roster 変更の SSE 配信

### Step 2: 脚本生成パイプライン
- [ ] 素材収集スクリプト（Phase のログを YAML にまとめる）
- [ ] 脚本生成プロンプト設計
- [ ] EP.6 で試作（手動実行）
- [ ] episodes/ ディレクトリ + 脚本 YAML フォーマット確定

### Step 3: Theater モード UI
- [ ] エピソード一覧画面
- [ ] エピソード再生画面
- [ ] Theater API（/api/episodes）
- [ ] 映画館トーンのデザイン

### Step 4: ens-couch 統合
- [ ] theater.sh 改修（Theater モードで起動）
- [ ] Couch 初期プロンプト v2
- [ ] モード切替（Control Room ↔ Theater）

---

## 10. 将来の拡張

- **自動ナレーション**: エピソードを音声合成で読み上げ（TTS）
- **BGM**: フリー BGM を Phase の雰囲気に合わせて自動選曲
- **キャラアイコン**: persona.yaml にアバター画像パスを追加
- **全話まとめ**: 全エピソードを1本の長編映画として連結表示
- **視聴者コメント**: Couch の感想を episodes/ に追記（コメンタリートラック）
- **スマホ対応**: レスポンシブレイアウトで移動中も鑑賞可能
