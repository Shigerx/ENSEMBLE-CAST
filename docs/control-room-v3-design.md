# Control Room v3 — エンターテイメント改修設計書

> show-live.sh と同じ情報を表示するだけでは芸がない。
> ブラウザだからこそできる演出で、撮影現場をエンターテイメントにする。

---

## 問題

| 現状 | 原因 |
|------|------|
| Control Room がつまらない。Couch（雑談）ばかり見てしまう | show-live.sh と同じデータを表示方法を変えただけ |
| ブランチツリーのアニメーションが消えた（v1 → v2 で退化） | v1 の SVG ツリーは 29 ブランチで崩壊 → v2 でテキストリストに変更 |
| show-live.sh の方が情報量多い | ターミナルはリフレッシュレートが高く、status.txt の詳細も表示 |
| 「見てて楽しい」要素がない | データダッシュボードに留まっている |

### 根本方針

**Control Room は「データ表示」ではなく「撮影現場の中継」。**
ブラウザの自由度を活かし、show-live.sh にはできない演出で差別化する。

---

## コンセプト: 映画の撮影現場を中継するテレビ番組

```
show-live.sh  = ラジオ中継（テキスト・音声のみ）
Control Room  = テレビ中継（映像・演出・グラフィック付き）
```

同じ「情報」でも、メディアが違えば体験が違う。
Control Room は以下の3原則で設計する:

1. **視覚演出** — アニメーション・エフェクト・色の変化で「動き」を見せる
2. **文脈のある情報** — 生データではなく、ストーリーとして提示する
3. **感情の増幅** — 成功を祝い、危機を演出する

---

## 画面構成（v3）

```
┌─ ENSEMBLE CAST — CONTROL ROOM ──────────────── Phase 7 ── LIVE ──┐
│                                                                    │
│  ┌─ STAGE ──────────────────────────────────────────────────────┐ │
│  │                                                              │ │
│  │     🌟              🔵              🔫                       │ │
│  │   giorno         bucciarati        mista                     │ │
│  │   ┌─────────┐   ┌─────────┐   ┌─────────┐                  │ │
│  │   │ 💬      │   │  ...    │   │ ✨done! │                  │ │
│  │   │"UIの調整│   │ 考え中  │   │  #27完了 │                  │ │
│  │   │ 中だ…" │   │         │   │         │                  │ │
│  │   └─────────┘   └─────────┘   └─────────┘                  │ │
│  │                                                              │ │
│  │          ✈️                 👮                                │ │
│  │        narancia           abbacchio                          │ │
│  │        ┌─────────┐       ┌─────────┐                       │ │
│  │        │ 💤 待機  │       │ 💤 待機  │                       │ │
│  │        └─────────┘       └─────────┘                       │ │
│  │                                                              │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  ┌─ TIMELINE ───────────────┐  ┌─ MISSION ───────────────────┐  │
│  │ 17:30 🌟 UI調整始めるぞ  │  │ Phase 7: Queue非同期化      │  │
│  │ 17:31 🔵 Consumer実装…   │  │ ████████░░░░ 2/4  50%      │  │
│  │ 17:32 🔫 ✅ #27完了！    │  │                             │  │
│  │ 17:33 🎬 #27 approved    │  │ #27 mista    ✓ approved    │  │
│  │       ────⚡────         │  │ #28 bucc     ● in_progress │  │
│  │ 17:35 🔵 ⚠️ ビルドエラー │  │ #29 giorno   ● in_progress │  │
│  │       （画面が赤く点滅）  │  │ #30 (依存待ち) ◌ pending  │  │
│  │ 17:36 🔵 修正完了、再ビルド│  │                             │  │
│  │       ────────────       │  │ Git: 12 commits today      │  │
│  │                          │  │ Branches: 3 active          │  │
│  └──────────────────────────┘  └─────────────────────────────┘  │
│                                                                    │
│  ┌─ COMMAND CONSOLE ───────────────────────────────────────────┐ │
│  │ > Producerに指示...                                 [送信] │ │
│  └─────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

### v2 → v3 の主な変更

| パネル | v2 | v3 |
|--------|----|----|
| Cast Status | ドットリスト（● 稼働 / ○ 待機） | **STAGE**: キャラカード + 吹き出し + アニメーション |
| Live Feed | テキストログの羅列 | **TIMELINE**: イベント演出付き（⚡区切り、エフェクト） |
| Branches | テキストリスト（折りたたみ） | MISSION パネルに統合（コンパクト表示） |
| Mission | Phase進捗 + タスクリスト | Phase進捗 + タスクリスト + Git統計 |
| Command Console | 変更なし | 変更なし |

---

## STAGE パネル（新設 — v2 Cast Status の進化形）

### コンセプト

Cast を「ステージ上の俳優」として視覚的に配置する。
各キャラがカード型で表示され、状態に応じてリアルタイムにアニメーションする。

### キャラカード

```
┌─────────────┐
│     🌟      │  ← persona.yaml の emoji
│   giorno    │  ← character_name
│  FE リード   │  ← dev_role（小さく薄く）
│ ┌─────────┐ │
│ │ 💬 台詞 │ │  ← activity.log の最新 chat/progress
│ └─────────┘ │
│  ● UI調整中  │  ← 現在のタスク名
└─────────────┘
```

### 状態別アニメーション

| 状態 | 視覚演出 | CSS |
|------|---------|-----|
| **稼働中**（処理中） | カード枠が緑に輝く + 吹き出しに最新メッセージ | `border-color: #22c55e; box-shadow: 0 0 12px rgba(34,197,94,.3)` + pulse |
| **考え中**（thinking） | 吹き出しに「...」がタイプライター風に点滅 | typing dots animation |
| **完了！** | カード全体が一瞬金色にフラッシュ → ✨パーティクル | `@keyframes flash-gold` + particle emitter |
| **待機中** | カードがグレーアウト + 少し縮小 | `opacity: 0.4; transform: scale(0.95)` |
| **blocked** | カード枠が赤く脈動 + ⚠️アイコン | `border-color: #ef4444` + pulse-blocked |
| **着任** | カードがステージ外からスライドイン | `@keyframes slide-in-up` |

### 吹き出し（Speech Bubble）

activity.log の最新 `chat` / `progress` イベントを吹き出しで表示。
- 新しいメッセージが来ると**フェードイン+スライドアップ**
- 一定時間（10秒）経過で**フェードアウト**
- blocked 時は吹き出しが赤くなり、理由を表示

### レイアウト（v3 scale 対応）

| scale | Cast数 | 配置 |
|-------|--------|------|
| small | 3-5名 | 1段 or 2段（上段3名 + 下段2名） |
| large | 6-12名 | ユニット別グループ（横並び × ユニット段） |

**v3 large 時のユニット表示:**
```
┌─ Unit: Frontend ──────────────┐ ┌─ Unit: Backend ──────────────┐
│  🌟 giorno  ✈️ narancia       │ │  🔵 bucciarati  👮 abbacchio │
│  [カード]    [カード]          │ │  [カード]       [カード]      │
└───────────────────────────────┘ └───────────────────────────────┘
```

---

## TIMELINE パネル（v2 Live Feed の進化形）

### コンセプト

ただのログ羅列ではなく、**ストーリーとして読めるタイムライン**。
重要イベントを演出で強調し、日常的なログは控えめに。

### イベント演出

| event | 演出 | 優先度 |
|-------|------|--------|
| `chat` | キャラ吹き出し（通常表示） | 低 |
| `progress` | 進捗バッジ（🔧 アイコン付き） | 低 |
| `task_done` | **✅ 完了バナー** — 緑背景でスライドイン + 効果音的パルス | 高 |
| `task_assign` | 📋 割り当て通知（タスク名 + 担当者） | 中 |
| `review` / `task_blocked` | **⚠️ 警告バナー** — 赤背景でフラッシュ | 高 |
| `phase_complete` | **🎉 Phase完了** — 金色の区切り線 + 全画面フラッシュ | 最高 |
| `arrival` | 🎬 着任（キャラ名 + スライドイン） | 中 |
| `ability` | ⚡ 必殺技発動（ability_name + エフェクト） | 高 |

### 区切り線

重要イベント（task_done, review, phase_complete）の前後に区切り線を入れ、
タイムラインにリズムを作る:

```
17:32 🔫 Queue Infrastructure 完了！
────── ⚡ #27 approved ──────
17:33 🎬 Director: #27 → merged to main
17:34 🔵 次のタスクに取りかかる
```

### blocked 演出（画面全体に影響）

Cast が blocked になった時:
1. TIMELINE に赤い警告バナー
2. STAGE の該当キャラカードが赤く脈動
3. **画面上部にアラートバー**が出現（「⚠️ bucciarati blocked: ビルドエラー」）
4. 解決時にアラートバーが緑に変わってフェードアウト

---

## MISSION パネル（v2 Mission + Branches 統合）

### 変更点

- Branches パネルを吸収（独立パネルとしては廃止）
- Git 統計を追加（コミット数、アクティブブランチ数）
- タスクリストに**マイクロ進捗バー**追加

### タスク表示

```
#27 🔫 mista    ████████████ ✓ approved
#28 🔵 bucc     ██████░░░░░░ ● in_progress  (Consumer実装)
#29 🌟 giorno   ███░░░░░░░░░ ● in_progress  (Progress UI)
#30 — (依存待ち) ░░░░░░░░░░░░ ◌ pending
```

進捗は status から推定:
- assigned: 25%
- in_progress: 50%（activity.log の progress イベント数で微調整可）
- in_review: 80%
- approved: 100%

### Git 統計（フッター）

```
Git: 12 commits today | 3 branches active | last merge 5min ago
```

### v3 large 対応

large 時はユニット別にタスクをグルーピング:

```
┌─ Frontend (2/3 done) ─┐  ┌─ Backend (1/2 done) ─┐
│ #27 giorno  ✓         │  │ #29 bucc    ●        │
│ #28 narancia ●        │  │ #30 abbac   ◌        │
│ #31 giorno  ◌         │  │                      │
└────────────────────────┘  └───────────────────────┘
```

---

## グローバル演出（画面全体に適用）

### Phase Complete セレモニー

Phase が完了した瞬間の特別演出:

1. 画面全体が一瞬白くフラッシュ
2. 金色のパーティクルが降り注ぐ（3秒間）
3. 中央に大きく「Phase N — COMPLETE」のタイトル表示（2秒）
4. 各 Cast カードが順に金色にハイライト（功績紹介）
5. 通常画面に戻る

### アラートシステム

画面上部に固定のアラートバーを配置:

| 状態 | 表示 |
|------|------|
| 通常 | 非表示 |
| blocked 発生 | 赤バー「⚠️ {cast} blocked: {理由}」 |
| レビュー reject | 黄バー「🔄 {cast} のタスク #{id} が差し戻し」 |
| 全タスク完了 | 緑バー「✅ 全タスク完了！Phase complete まもなく」 |

### 環境音（将来拡張・オプション）

- タスク完了: 短い達成音（チャイム）
- blocked: 警告音（低い）
- Phase complete: ファンファーレ
- **デフォルトはミュート。Owner がトグルで ON/OFF。**

---

## SSE イベント拡張

### 新規イベントタイプ

v2 の SSE は `activity`, `dashboard`, `roster` の3種類。v3 で追加:

| イベント | トリガー | データ |
|---------|---------|--------|
| `status_change` | `*_status.txt` 変更 | `{ slug, state, task_title, task_id }` |
| `branch` | git ブランチ変更 | `{ branches: [...] }` |

### status_change の活用

Cast の `*_status.txt` はリアルタイムで更新される。
これを SSE で配信すれば、STAGE のキャラカードを即座に更新できる。

```python
# theater-server.py に追加
# status.txt の mtime を監視
for slug in cast_slugs:
    status_path = BASE / 'logs' / f'{slug}_status.txt'
    if status_path.exists():
        mt = status_path.stat().st_mtime
        if mt > last_status_mtime.get(slug, 0):
            last_status_mtime[slug] = mt
            # SSE で配信
            send_sse('status_change', { slug, state, ... })
```

---

## API 変更

### 新規・変更

| エンドポイント | 変更 | 説明 |
|---|---|---|
| `GET /api/cast` | 拡張 | `latest_message`（最新の chat/progress）を追加 |
| `GET /api/events` | 拡張 | `status_change`, `branch` イベントを追加 |
| `GET /api/stats` | 新規 | Git 統計（本日のコミット数、ブランチ数、最終マージ時刻） |

### GET /api/cast レスポンス拡張

```json
{
  "cast": [
    {
      "slug": "giorno",
      "character_name": "ジョルノ・ジョバァーナ",
      "emoji": "🌟",
      "color": "#f0c040",
      "state": "処理中",
      "task_id": 29,
      "task_title": "Progress UI",
      "latest_message": {
        "event": "chat",
        "message": "UIの調整中だ…ゴールド・エクスペリエンス！",
        "timestamp": "2026-02-08T17:30:15"
      }
    }
  ]
}
```

---

## v3 large 対応（scale: large）

### ユニット概念の視覚化

large 時は STAGE を**ユニット別に区切る**:

```
┌─ STAGE ──────────────────────────────────────────────┐
│  ┌─ Unit: Frontend ─────────┐ ┌─ Unit: Backend ────┐│
│  │  Director: 🎬 (hidden)   │ │  Director: 🎬      ││
│  │  🌟 giorno  ✈️ narancia  │ │  🔵 bucc  👮 abba  ││
│  │  [cards...]               │ │  [cards...]         ││
│  └───────────────────────────┘ └─────────────────────┘│
└───────────────────────────────────────────────────────┘
```

### Director / LP の表示

| ロール | 表示 |
|--------|------|
| Director（small） | STAGE には表示しない（裏方） |
| Director（large） | ユニットヘッダーに小さく表示 |
| LP | MISSION パネルに「LP: {status}」として表示 |
| Producer | Command Console 横に「EP: {status}」として表示 |

### ユニット間通信の可視化（将来拡張）

ユニット間でメッセージがやり取りされた時、STAGE 上に矢印アニメーション:
```
[Frontend Unit] ──→ [Backend Unit]
              "API 仕様変更依頼"
```

---

## 実装計画

### Phase 1: STAGE パネル（最優先）

最も差別化効果が高い。Live Feed → TIMELINE は後回しでもいい。

1. Cast Status パネルを STAGE に置き換え
2. キャラカード（emoji + 名前 + 状態アニメーション）
3. 吹き出し（activity.log の最新メッセージ）
4. status_change SSE イベント追加

### Phase 2: TIMELINE 演出

1. Live Feed に区切り線・バナー演出追加
2. イベント優先度による表示差別化
3. blocked 時のアラートバー

### Phase 3: MISSION 統合 + グローバル演出

1. Branches を MISSION に統合
2. Git 統計追加
3. Phase Complete セレモニー
4. タスクのマイクロ進捗バー

### Phase 4: v3 large 対応

1. ユニット別 STAGE レイアウト
2. ユニット別タスクグルーピング
3. LP / Director の表示

---

## 技術的注意事項

### パフォーマンス

- STAGE のアニメーションは CSS だけで実装（JS アニメーションは負荷が高い）
- パーティクルエフェクトは `<canvas>` で最小限に（Phase Complete 時のみ）
- SSE のポーリング間隔は現行の 1秒 を維持

### 互換性

- show-live.sh は引き続き動作する（ターミナル環境用）
- Theater モード（映画鑑賞）は変更なし
- API は後方互換（既存フィールドは削除しない、追加のみ）

### ファイル構成（変更なし）

```
ui/control-room.html  ← この1ファイルを改修
scripts/theater-server.py  ← SSE イベント追加 + /api/cast 拡張
```

単一HTMLファイル方針は維持。npm/ビルド不要。
