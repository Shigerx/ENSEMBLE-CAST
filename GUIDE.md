# ENSEMBLE CAST — Owner操作ガイド

> 映画のキャラクターたちがあなたのプロジェクトを開発する、マルチエージェントシステム

---

## クイックスタート

### 1. 起動

```bash
# WSL2 または Git Bash で実行
bash launch-ensemble.sh
```

起動すると:
- 前回データがあれば「新規/継続」を選択
- tmuxセッション `ensemble` が作成される
- Producer と Director のペインが起動

### 2. セッションに入る

```bash
tmux attach-session -t ensemble
```

### 3. Producerと対話

左ペイン（Producer）があなたの対話窓口です。

---

## 外部プロジェクトでの使い方

ENSEMBLE-CASTは「親オーケストレーター」として動作します。
対象プロジェクトとは別のディレクトリで起動し、外部プロジェクトを操作します。

### ディレクトリ構成

```
~/antigravity/
├── ENSEMBLE-CAST/          ← 制御センター（ここでtmuxを起動）
│   ├── config/
│   │   └── production.yaml ← target_path で対象を指定
│   ├── launch-ensemble.sh
│   └── ...
│
└── my-new-project/         ← 実際の作業対象（別リポジトリ）
    ├── src/
    ├── package.json
    └── ...
```

### 設定方法

1. **ENSEMBLE-CASTディレクトリで起動**:
   ```bash
   cd ~/antigravity/ENSEMBLE-CAST
   bash launch-ensemble.sh
   ```

2. **Producerに対象プロジェクトを伝える**:
   ```
   映画は「オーシャンズ11」で、
   ~/antigravity/my-new-project にあるReactアプリを改修したい
   ```

3. **production.yaml に記録される**:
   ```yaml
   project:
     name: "my-new-project"
     target_path: "/mnt/c/Users/shige/antigravity/my-new-project"
     tech_stack: ["React", "TypeScript"]
   ```

### 複数プロジェクトの切り替え

1. 現在の作業を終了（または中断）
2. `config/production.yaml` を更新（または新規起動時に別プロジェクトを指定）
3. Cast達が新しいプロジェクトで作業開始

### メリット

- **ENSEMBLE-CASTは1箇所で管理** — アップデートが楽
- **プロジェクト側を汚さない** — `.ensemble/` などのゴミが入らない
- **複数プロジェクトを切り替え可能** — production.yaml を変えるだけ

**最初に聞かれること:**
1. **映画**: どの映画のキャラクターを使うか（例: オーシャンズ11、ホロライブ、アベンジャーズ）
2. **プロジェクト**: 何を作りたいか（例: TODOアプリ、ブログシステム）

**例:**
```
映画は「ねぽらぼ」で、Reactで家計簿アプリを作りたい
```

---

## 画面構成

```
┌─────────────────────┬─────────────────────┐
│                     │                     │
│   🎬 Producer       │   🎬 Director       │
│   （あなたの窓口）    │   （演出・タスク管理）│
│                     │                     │
├──────────┬──────────┼──────────┬──────────┤
│ 🎭 Cast1 │ 🎭 Cast2 │ 🎭 Cast3 │ 🎭 Cast4 │
│          │          │          │          │
└──────────┴──────────┴──────────┴──────────┘
```

- **Producer（左上）**: あなたと対話。ここに指示を出す
- **Director（右上）**: キャスティング、タスク配布を行う
- **Cast（下段）**: 実際にコードを書く。キャラクターとして振る舞う

---

## tmux操作早見表

| 操作 | キー |
|------|------|
| ペイン間移動 | `Ctrl+B` → 矢印キー |
| セッションからデタッチ | `Ctrl+B` → `d` |
| スクロールモード | `Ctrl+B` → `[` （qで終了） |
| セッション一覧 | `tmux ls` |
| セッションに戻る | `tmux attach -t ensemble` |

**マウス操作**: 有効になっています。クリックでペイン選択、スクロール可能。

---

## 監視ツール

### ダッシュボード（テキスト）

```bash
bash scripts/show-dashboard.sh
```
- dashboard.md の内容を整形表示

### ライブモニター（RPG風）

```bash
# 1回表示
bash scripts/show-live.sh

# 2秒ごと自動更新（Ctrl+Cで終了）
bash scripts/show-live.sh --watch
```

表示内容:
- キャスト状況（誰が何をしているか）
- タスクフロー（進捗状況）
- アクティビティログ（最新20件）

---

## 演劇への干渉方法

### 基本ルール

**あなた（Owner）が話しかけるのはProducerのみ。**

他のペインには直接話しかけないでください（システムが混乱します）。

### 干渉パターン

#### 1. 状況確認
```
今どんな状況？
```
→ Producerがdashboard.mdを見て報告

#### 2. 方針変更
```
やっぱりTypeScriptじゃなくてJavaScriptで
```
→ ProducerがDirectorに伝達 → 全体に反映

#### 3. タスク追加
```
ダークモード対応も追加して
```
→ 新タスクとして配布される

#### 4. 優先度変更
```
UIより先にAPI接続を優先して
```
→ タスク順序が調整される

#### 5. 問題への対応
```
🚨要対応に「DBスキーマ未決定」って出てるけど、PostgreSQLでこの構造で
```
→ ブロッカーが解消される

#### 6. 強制停止
```
全員ストップ
```
→ 作業を中断して状況報告

#### 7. 特定キャストへの指示
```
botanに直接聞きたい: アーキテクチャの理由を説明して
```
→ Producerが中継してくれる

---

## ファイル構成

```
ENSEMBLE-CAST/
├── CLAUDE.md           # 全エージェント共通ルール
├── GUIDE.md            # このファイル
├── dashboard.md        # 進捗ダッシュボード（Directorが更新）
├── launch-ensemble.sh  # 起動スクリプト
│
├── config/
│   ├── panes.yaml      # ペインID管理
│   └── production.yaml # 映画・プロジェクト情報
│
├── instructions/
│   ├── producer.md     # Producer指示書
│   ├── director.md     # Director指示書
│   └── cast_template.md # Cast指示書テンプレート
│
├── cast/
│   ├── roster.yaml     # キャスト一覧
│   └── members/
│       └── <slug>/
│           ├── persona.yaml      # キャラクター設定
│           ├── chronicle.yaml    # 行動履歴
│           └── relationships.yaml # 関係性
│
├── queue/
│   ├── producer_to_director.yaml # Producer→Director指示
│   ├── tasks/<slug>.yaml         # 各キャストのタスク
│   └── reports/<slug>_report.yaml # 各キャストの報告
│
├── logs/
│   ├── activity.log              # アクティビティログ
│   ├── director_status.txt       # Directorステータス
│   └── <slug>_status.txt         # 各キャストステータス
│
├── context/
│   └── <project>.md    # プロジェクトコンテキスト
│
├── memory/
│   └── global_context.md # グローバル設定
│
└── scripts/
    ├── wake-agent.sh     # エージェント起床
    ├── add-cast-pane.sh  # キャスト追加
    ├── show-dashboard.sh # ダッシュボード表示
    ├── show-live.sh      # ライブモニター
    └── kill-all.sh       # 全終了
```

---

## 典型的なフロー

### 新規プロジェクト開始

1. `bash launch-ensemble.sh` → 「新規スタート」選択
2. Producerが映画とプロジェクトをヒアリング
3. Directorがキャスティング実行（4〜8名）
4. 各Castがキャラクターリサーチ → 着任挨拶
5. Directorがタスク配布
6. 開発スタート

### 作業中の確認

```bash
# 別ターミナルで
bash scripts/show-live.sh --watch
```

### 完了確認

dashboard.mdの「✅ 本日の戦果」を確認

---

## トラブルシューティング

### エージェントが止まっている

**原因**: コンパクション（コンテキストリセット）が発生した可能性

**対処**: Producerペインで:
```
Director起こして
```
または直接Directorペインに入って:
```
CLAUDE.md を読んで再開して
```

### キャストが応答しない

**対処**: Producerに:
```
botanが止まってるみたい、状況確認して
```

### 全部やり直したい

```bash
bash scripts/kill-all.sh
bash launch-ensemble.sh
# → 「新規スタート」を選択
```

### tmuxセッションが残っている

```bash
tmux kill-session -t ensemble
```

---

## 注意事項

### やってはいけないこと

1. **Producer以外に直接話しかける**
   - システムの階層構造が崩れる

2. **dashboard.mdを手動編集する**
   - Directorだけが更新する決まり

3. **queue/のファイルを手動編集する**
   - 通信が混乱する

### コスト意識

- 各エージェントはClaude APIを消費します
- キャストが多いほどコストが増加
- 通常4〜6名が適切

---

## 再開方法

```bash
# 前回の続きから
bash launch-ensemble.sh
# → 「前回の続きから再開」を選択

# セッションに入る
tmux attach -t ensemble

# Producerに状況確認
今の状況教えて
```

---

## コマンドチートシート

```bash
# 起動
bash launch-ensemble.sh

# セッション接続
tmux attach -t ensemble

# ライブモニター
bash scripts/show-live.sh --watch

# ダッシュボード
bash scripts/show-dashboard.sh

# 全終了
bash scripts/kill-all.sh

# セッション強制終了
tmux kill-session -t ensemble
```

---

楽しい開発を！ 🎬
