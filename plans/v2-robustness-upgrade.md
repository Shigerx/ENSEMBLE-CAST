# ENSEMBLE-CAST v2 — 堅牢性アップグレード設計書

> ステータス: 設計完了・実装待ち
> 作成日: 2026-02-07
> 目的: 小〜中規模の「おもちゃ」から、中〜大規模に耐える実用ツールへの進化
> 作成者: froglogv2 セッションでの Owner + Claude 協議結果

---

## 背景

ENSEMBLE-CAST は映画メタファーによるマルチエージェント開発ツール。
小〜中規模プロジェクトでは機能するが、以下の **5つの壁** が大規模化を阻んでいる。

### 5つの壁

| # | 壁 | 現状 | 影響 |
|---|-----|------|------|
| 1 | ファイル競合 | 信頼ベースで「触らない前提」 | 統合時に後勝ちで先の変更消失 |
| 2 | 依存関係の強制力なし | `depends_on` はあるが Cast が無視可能 | 未完了タスクの成果物を前提に作業開始 |
| 3 | Git ブランチ戦略なし | 全員が同一ブランチで作業 | ファイル競合・ロールバック不能 |
| 4 | エラー伝播が遅い | ビルド失敗が下流に波及してから発覚 | 統合時に爆発 |
| 5 | Director スケーリング限界 | Cast 8名で Director の認知負荷が限界 | plans/multi-team-architecture.md で構想済み |

本設計は **壁1〜4を解決** する。壁5（マルチチーム）は別設計として切り出す。

---

## 改善1: Git ブランチ分離

### 概要
Cast ごとに作業ブランチを作成し、ファイル競合を根本解決する。

### 変更内容

#### `instructions/director.md` に追記

```markdown
## 🔴 Git ブランチ管理（v2 追加）

### タスク配布時のブランチ作成

各 Cast にタスクを配布する際、**専用ブランチを作成**する:

1. メインブランチの最新を取得:
   ```bash
   cd <target_path>
   git checkout main && git pull origin main
   ```

2. Cast 用ブランチを作成:
   ```bash
   git checkout -b cast/<slug>/<task-id>-<短い説明>
   git checkout main  # Director 自身は main に戻る
   ```

3. タスク YAML にブランチ名を記載:
   ```yaml
   tasks:
     - id: 1
       branch: "cast/botan/1-deadline-feature"  # ← 追加
       # ... 他のフィールド
   ```

### 統合タスクのマージフロー

統合タスク（depends_on あり）の場合:

1. 依存タスクの全ブランチを統合ブランチにマージ:
   ```bash
   git checkout -b cast/<slug>/<task-id>-integration
   git merge cast/<依存slug1>/<依存task-id>-<説明> --no-edit
   git merge cast/<依存slug2>/<依存task-id>-<説明> --no-edit
   ```

2. コンフリクトがあれば `status: blocked` で報告

### レビュー承認後のマージ

Director がレビュー承認後に main へマージ:
```bash
cd <target_path>
git checkout main
git merge cast/<slug>/<task-id>-<説明> --no-edit
git branch -d cast/<slug>/<task-id>-<説明>
```
```

#### `instructions/cast_template.md` に追記

```markdown
## 🔴 Git ブランチルール（v2 追加）

### タスク開始時

タスクの `branch` フィールドで指定されたブランチに切り替える:
```bash
cd <target_path>
git checkout <branch名>
```

### コミットルール

- 作業は必ず指定ブランチ上で行う
- main ブランチには直接コミットしない
- コミットメッセージ: `[#<task-id>] <内容>`
```

#### `queue/tasks/<slug>.yaml` スキーマ変更

```yaml
tasks:
  - id: 1
    title: "..."
    branch: "cast/<slug>/<id>-<説明>"  # ← 新規追加（必須）
    # ... 既存フィールド
```

### 影響範囲
- `instructions/director.md`: ブランチ管理セクション追加
- `instructions/cast_template.md`: ブランチ切替ルール追加
- `instructions/reviewer.md`: レビュー時のブランチ checkout 追加
- タスク YAML スキーマ: `branch` フィールド追加

---

## 改善2: 依存タスクの wake 制御

### 概要
`depends_on` を Director が強制チェックし、依存タスク未完了なら wake しない。

### 変更内容

#### `instructions/director.md` — タスク配布セクションに追記

```markdown
## 🔴 依存タスクの強制チェック（v2 追加）

### タスク配布時の依存チェック

タスクに `depends_on` がある場合、**依存タスクの完了を確認してから wake する**。

```
タスク配布判断フロー:
  ↓
depends_on がある？
  ├─ NO → 即座に wake
  └─ YES → 依存タスクの status を確認
       ├─ 全て approved → wake
       ├─ 一部未完了 → wake しない（pending_tasks に記録）
       └─ 一部 rejected → 依存の修正完了まで待機
```

### pending_tasks の管理

依存待ちタスクは `queue/pending_tasks.yaml` に記録:

```yaml
pending_tasks:
  - task_id: 3
    assigned_to: "polka"
    depends_on: [1, 2]
    waiting_for:
      - task_id: 1
        status: "in_progress"  # まだ完了していない
      - task_id: 2
        status: "approved"     # 完了済み
    created_at: <timestamp>
```

### 起床時のペンディングチェック

起床時の Full Scan に追加:
1. `queue/reports/` を全スキャン（既存）
2. **`queue/pending_tasks.yaml` をチェック**（追加）
   - 依存タスクが全て approved になっていたら:
     - pending_tasks から削除
     - 対象 Cast のタスク YAML を書き込み
     - Cast を wake
```

#### 新規ファイル: `queue/pending_tasks.yaml`

Director が管理する依存待ちタスクのキュー。

### 影響範囲
- `instructions/director.md`: 依存チェックフロー追加、wake 判断フロー更新
- `queue/pending_tasks.yaml`: 新規ファイル（Director 管理）
- CLAUDE.md ファイル所有権マトリクス: pending_tasks.yaml を追加

---

## 改善3: ファイルオーナーシップ制

### 概要
タスク配布時にファイルの排他的所有権を宣言し、競合を事前検出する。

### 変更内容

#### `instructions/director.md` に追記

```markdown
## 🔴 ファイルオーナーシップ管理（v2 追加）

### タスク配布時のファイル宣言

各タスクに `owned_files`（排他）と `shared_files`（統合時に調整）を明記:

```yaml
tasks:
  - id: 1
    owned_files:          # このCast だけが書き込めるファイル
      - src/components/DueDatePicker.tsx
      - src/components/DueDateDisplay.tsx
    shared_files:         # 統合タスクで最終調整するファイル
      - src/App.tsx
```

### 競合チェック（タスク配布前に実施）

新しいタスクを配布する前に、**既存タスクの owned_files と重複がないか確認**:

```
チェックフロー:
  ↓
新タスクの owned_files を列挙
  ↓
既存の全 active タスクの owned_files と比較
  ↓
重複あり？
  ├─ YES → タスクを分割するか、依存関係にして直列化
  └─ NO → 配布OK
```

### ファイルレジストリ

現在のファイル所有状況を `queue/file_registry.yaml` で管理:

```yaml
# Director が管理。タスク配布/完了時に更新
registry:
  - file: "src/components/DueDatePicker.tsx"
    owner: "botan"
    task_id: 1
    type: exclusive
  - file: "src/App.tsx"
    owner: null          # shared — 統合タスクまで誰も排他取得しない
    type: shared
    pending_integrator: "polka"  # 統合担当
```
```

#### `instructions/cast_template.md` に追記

```markdown
## 🔴 ファイルオーナーシップルール（v2 追加）

- タスクの `owned_files` に記載されたファイルのみ作成・編集できる
- `owned_files` に含まれないファイルを変更する必要がある場合:
  → `status: blocked` で Director に報告（追加ファイルのリクエスト）
- `shared_files` のファイルは読み取りのみ可。書き込みは統合タスクで行う
```

#### 新規ファイル: `queue/file_registry.yaml`

### 影響範囲
- `instructions/director.md`: オーナーシップ管理セクション追加
- `instructions/cast_template.md`: ファイル制約ルール追加
- `queue/file_registry.yaml`: 新規ファイル
- タスク YAML スキーマ: `owned_files`, `shared_files` フィールド追加
- CLAUDE.md ファイル所有権マトリクス: file_registry.yaml を追加

---

## 改善4: Reviewer 常時監視（ゲートキーパー強化）

### 概要
Reviewer のチェックを強化し、エラーの早期発見を実現する。

### 変更内容

#### `instructions/reviewer.md` に追記

```markdown
## 🔴 強化チェック項目（v2 追加）

### チェック8: OWNERSHIP（v2 追加・必須）

タスクの `owned_files` と実際の変更ファイルを照合:
- `owned_files` 以外のファイルが変更されていないか確認
- 変更されている場合: ❌ rejected（ファイル所有権違反）

### チェック9: BRANCH（v2 追加・必須）

正しいブランチで作業されているか確認:
```bash
cd <target_path>
git log --oneline cast/<slug>/<task-id>-* | head -5
```
- main ブランチへの直接コミットがないか確認
- 変更されている場合: ❌ rejected（ブランチルール違反）

### チェック10: DEPENDENCY（v2 追加・depends_on がある場合）

統合タスクで依存タスクの成果物が正しく使用されているか確認:
- 依存タスクの `owned_files` が import されているか
- 独自に再実装されていないか（既存の INTEGRATION チェックの強化版）
```

#### `instructions/director.md` — レビュー後のマージ追加

```markdown
### レビュー approved 後の追加アクション（v2 追加）

1. Cast のブランチを main にマージ:
   ```bash
   cd <target_path>
   git checkout main
   git merge cast/<slug>/<task-id>-<説明> --no-edit
   ```

2. マージ成功を確認後、ブランチ削除:
   ```bash
   git branch -d cast/<slug>/<task-id>-<説明>
   ```

3. `queue/file_registry.yaml` から該当タスクのエントリを削除

4. **マージ後ビルドチェック**（任意だが推奨）:
   ```bash
   cd <target_path>
   npm run build
   ```
   失敗した場合: マージをリバートし、Cast に修正タスクを配布
```

### 影響範囲
- `instructions/reviewer.md`: チェック8〜10追加
- `instructions/director.md`: マージフロー追加

---

## 改善5（部分）: Director 認知負荷軽減

### 概要
壁5のフル対応（マルチチーム）は `multi-team-architecture.md` に譲るが、
Director の負荷を下げる軽量な改善をここで行う。

### 変更内容

#### `instructions/director.md` に追記

```markdown
## 🔴 タスク配布の自動化ヒント（v2 追加）

### バッチ配布パターン

独立したタスクは一括で配布し、1回の停止で済ませる:

```
独立タスク群: [#1, #2, #3] → 全員に一括 wake → 停止
依存タスク: [#4 depends_on #1,#2] → pending_tasks に登録 → 完了時に自動 wake
```

### ダッシュボード簡易化

Cast 4名以上の場合、dashboard.md に進捗サマリーを追加:

```markdown
## 📊 進捗サマリー
- 総タスク: 8
- 完了(approved): 3 (37.5%)
- 進行中: 3
- ペンディング(依存待ち): 2
- ブロック: 0
```
```

---

## 実装順序

```
Phase 1（低コスト・高効果）
  ├── 改善1: Git ブランチ分離
  └── 改善2: 依存タスクの wake 制御

Phase 2（中コスト・中効果）
  ├── 改善3: ファイルオーナーシップ制
  └── 改善4: Reviewer 強化チェック

Phase 3（別設計）
  └── 改善5: マルチチーム（multi-team-architecture.md）
```

### Phase 1 の具体的な作業

1. `instructions/director.md` に Git ブランチ管理セクションを追加
2. `instructions/cast_template.md` にブランチルールを追加
3. `instructions/reviewer.md` にブランチチェックを追加
4. `instructions/director.md` に依存チェックフローを追加
5. `CLAUDE.md` のレース条件セクションを更新（ブランチ分離に言及）
6. `queue/pending_tasks.yaml` の初期ファイルを作成
7. CLAUDE.md のファイル所有権マトリクスを更新

### Phase 2 の具体的な作業

1. `instructions/director.md` にオーナーシップ管理セクションを追加
2. `instructions/cast_template.md` にファイル制約ルールを追加
3. `instructions/reviewer.md` にチェック8〜10を追加
4. `instructions/director.md` にマージ後フローを追加
5. `queue/file_registry.yaml` の初期ファイルを作成
6. CLAUDE.md のファイル所有権マトリクスを更新

---

## 変更対象ファイル一覧

| ファイル | 変更種別 | Phase |
|---------|---------|-------|
| `instructions/director.md` | 大幅追記 | 1, 2 |
| `instructions/cast_template.md` | 追記 | 1, 2 |
| `instructions/reviewer.md` | 追記 | 1, 2 |
| `CLAUDE.md` | マトリクス更新 | 1, 2 |
| `queue/pending_tasks.yaml` | 新規 | 1 |
| `queue/file_registry.yaml` | 新規 | 2 |

---

## 注意事項

- **既存のワークフローを壊さない**: 全て追記ベース。既存の指示は変更しない
- **段階的導入**: Phase 1 だけでも大幅改善。Phase 2 は Phase 1 の運用後に判断可能
- **Agent Teams 統合**: 将来 Claude Code の Agent Teams が安定したら、send-keys 部分を置き換え可能。ペルソナ・キャスティング・レビューの仕組みはそのまま活用できる
- **テスト**: Phase 1 完了後、小規模プロジェクト（nepolabo-todo 等）で検証してから大規模適用

---

## 参考: 議論の経緯

この設計は froglogv2 プロジェクトのセッション（2026-02-07）で、
FROGLOG の CLAUDE.md ブラッシュアップ → Agent Teams 調査 → ENSEMBLE-CAST 改善
という流れで生まれた。

Agent Teams の現状（Windows クラッシュバグ #23435、tmux send-keys 文字化け #23615）を踏まえ、
当面は ENSEMBLE-CAST の堅牢性を先に上げる方針で合意。
