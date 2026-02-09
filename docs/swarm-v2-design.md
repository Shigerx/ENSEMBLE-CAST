# Swarm v2 設計 — クロスAIディベート

> **起点**: ENSEMBLE-CAST v4 アーキテクチャ（docs/ensemble-v4-architecture.md）で合意した Phase 計画に基づき、
> Swarm スキル（`.claude/skills/swarm/SKILL.md`）を v4 対応に再設計する。
>
> **ディベート参加者**:
> - **Polnareff**（Advocate / 設計擁護者）: Claude Opus 4.6
> - **Fugo**（Challenger / 批判者）: Claude Opus 4.6
>
> **対象**: 2つのSwarmバリアント設計
> 1. **v4 実装 Swarm** — ENSEMBLE-CAST フレームワーク自体の開発（P1-P6）
> 2. **Cast 運用 Swarm** — Cast メンバーがタスク内で並列化する際に使用

---

## 現行 Swarm の課題

現行の `.claude/skills/swarm/SKILL.md`（593行）は汎用的な並列開発スキルだが、v4 アーキテクチャとの統合ポイントが欠けている:

1. **フレームワーク開発 vs アプリ開発の区別がない**: ENSEMBLE-CAST 自体の Markdown/YAML 変更と、F.L.A.R.E. のようなコード開発で同じルールを適用
2. **v4 固有の品質チェックがない**: chronicle handoff、CI 連携、Red Team 通知が未組み込み
3. **TDD がすべてに強制される**: Markdown/YAML 変更に TDD は不適用
4. **Cast 運用時の追加要件が未定義**: activity.log 記録、report.yaml 生成、worktree パス

---

## Position A: Polnareff の初期設計（Round 1）

### 設計方針

2つの独立したプロファイルファイルに分離する案:
- `.claude/skills/swarm/profiles/framework.md` — フレームワーク開発用
- `.claude/skills/swarm/profiles/cast.md` — Cast 運用用

### 提案内容

#### 1. Phase 0: Design Debate 統合

Swarm 実行前に Design Debate Protocol を Phase 0 として組み込む。Advocate + Challenger サブエージェントを Swarm 内で起動し、設計レビューを実施してから開発に入る。

#### 2. フレームワーク固有の Quality Gate

framework.md プロファイルに以下の QG 項目を追加:

| 項目 | 検証内容 |
|------|---------|
| セクション番号重複チェック | CLAUDE.md 等のセクション番号が重複していないか |
| ファイル所有権マトリクス整合 | 新規ファイルが所有権テーブルに追加されているか |
| 指示書クロスリファレンス | 変更された仕様が全指示書で参照されているか |
| コンパクション復帰手順 | 新規ファイルがコンパクション復帰手順に含まれているか |
| forbidden_actions 確認 | 新規ロールに適切な禁止事項が定義されているか |

#### 3. Cast 運用固有の機能

cast.md プロファイルに以下を追加:

- **CI 連携**: Phase 3 で `queue/ci_results/` を参照し、CI 結果を QG に統合
- **chronicle handoff**: Phase 5（最終報告）で chronicle.yaml の handoff セクションを更新
- **Red Team 通知**: 特定条件下で Red Team レビューをフラグ付け
- **activity.log 記録**: Swarm 開始/完了/QG結果の 6 エントリを activity.log に追記

#### 4. TDD 強制（両プロファイル共通）

全開発に TDD を適用。テストファーストを強制。

---

## Position B: Fugo の反論（Round 1）

### 6 つの問題点

#### Issue #1 [HIGH]: プロファイル分離は過剰

**反論**: Claude Code のスキル実行メカニズムでは、`$ARGUMENTS` は単純な文字列展開。SKILL.md は 1 ファイルがプロンプトとして注入される。プロファイル分離すると:

- SKILL.md がプロファイルを自動ロードする仕組みがない（Read tool で手動読み込みが必要）
- `$ARGUMENTS` は設計書パスに使用済み。プロファイル名を渡す余地がない
- 2ファイル管理は保守コスト増

**提案**: 1 ファイル内にセクションアノテーションで条件分岐を記述:

```markdown
### Quality Gate 項目

**共通（全開発）:**
- テスト実行 + 結果確認
- ビルド確認

**[フレームワーク開発のみ]:**
- セクション番号重複チェック
- ファイル所有権マトリクス整合
```

Orchestrator が設計書の内容から「フレームワーク開発か否か」を判断し、該当セクションを適用する。

#### Issue #2 [MEDIUM]: Design Debate は Swarm のスコープ外

**反論**: v4 アーキテクチャで合意した Design Debate Protocol は **Director が Phase 開始前に実行する**もの。Swarm は Director から委任された「実装作業」を担当する。

- Design Debate → Director のスコープ（Phase 開始前）
- Swarm → 実装のスコープ（Phase 開始後）

Cast が Swarm を使う場合、Cast には Design Debate を主催する権限がない（Director 判断事項）。Phase 0 として Swarm に組み込むと、Cast が Swarm を呼んだ時に Design Debate が走ってしまう。

**提案**: Design Debate は Swarm から除外。Director の指示書に組み込む。

#### Issue #3 [LOW]: QG 項目のギャップ

Polnareff の QG リストに以下が不足:

- **クロスリファレンス**: 「変更された仕様が全指示書で参照されているか」は方向性が逆。指示書が仕様を参照するのであって、仕様が指示書を参照するのではない
- **forbidden_actions**: 新規ロール追加時の禁止事項チェックが漏れている

#### Issue #4 [MEDIUM]: CI 連携のタイミング問題

**反論**: CI（ci.js）は post-commit hook で非同期実行される。Swarm の Phase 3 時点で CI 結果が存在するとは限らない。

```
Developer Agent がコミット → post-commit hook → ci.js が非同期でビルド+テスト
                                                    ↓
                                              結果が出るまで数秒〜数十秒
                                                    ↓
                              Phase 3 で結果を見ようとした時、まだ完了していない可能性
```

**提案**: Orchestrator が Phase 3/4 で直接ビルド・テストコマンドを実行する（現行通り）。CI 結果は「補足情報」として参照するが、QG の主たる証拠にはしない。

#### Issue #5 [LOW]: activity.log のエントリ数

Swarm 1 回で 6 エントリは多すぎる。Cast の activity.log は `chat` と `progress` イベントのみ許可されている（CLAUDE.md Section 7）。

**提案**: 3 エントリに削減:
1. `progress`: Swarm 開始（タスク概要）
2. `progress`: QG 結果（PASS/FAIL）
3. `progress`: Swarm 完了（作成ファイル概要）

#### Issue #6 [HIGH]: TDD はフレームワーク開発に適用不可

**反論**: ENSEMBLE-CAST フレームワークの P1-P6 は主に Markdown/YAML の変更:

- `CLAUDE.md` のルール追記
- `instructions/*.md` の指示書更新
- `config/*.yaml` の設定追加

これらに「テストファースト」は意味をなさない。テスト対象がない。

**提案**: フレームワーク開発では TDD の代わりに **整合性チェックリスト** を適用:

```markdown
### フレームワーク整合性チェックリスト
- [ ] 変更したルールが他セクションと矛盾していないか
- [ ] 新規ファイルがファイル所有権マトリクスに追加されているか
- [ ] コンパクション復帰手順が更新されているか
- [ ] 新規ルールに違反する既存コードがないか（Grep で確認）
```

実行可能コード（ci.js、スクリプト等）に対してのみ TDD を適用する。

---

## Round 2: Polnareff の応答

### 判定サマリー

| Fugo の指摘 | Polnareff の判定 | 対応 |
|-------------|-----------------|------|
| #1 プロファイル分離は過剰 | ✅ **受け入れ** | 1 ファイルにセクションアノテーション方式を採用 |
| #2 Design Debate はスコープ外 | ✅ **受け入れ** | Phase 0 を削除。Director 指示書に委任 |
| #3 QG 項目のギャップ | ✅ **受け入れ** | クロスリファレンスの方向性を修正、forbidden_actions を追加 |
| #4 CI 連携のタイミング | ✅ **受け入れ** | Orchestrator 直接実行を主、CI を補助に |
| #5 activity.log エントリ数 | ✅ **受け入れ** | 6 → 3 エントリに削減 |
| #6 TDD のフレームワーク適用 | ✅ **受け入れ** | 実行可能コードのみ TDD、Markdown/YAML は整合性チェックリスト |

**全 6 指摘を受け入れ（6/6）。**

### Polnareff 自己修正: Red Team 通知の簡素化

当初提案の Red Team 通知は条件判定ロジック（「セキュリティ関連の変更があれば通知」等）を Swarm 内に持たせていたが、AI が条件を正確に判断するのは困難。

**修正**: フラグベースに変更。
- **Director → Cast**: タスク YAML に `red_team_review: true` フラグを設定
- **Cast → Director**: report.yaml に `red_team_requested: true` フラグを設定（自己判断で追加も可）
- **Swarm 内**: フラグの有無だけを見る。条件判定ロジックは持たない

---

## Round 2.5: Fugo の確認応答

### 判定サマリー

| Polnareff の修正 | Fugo の判定 |
|-----------------|-------------|
| 全 6 点の受け入れ | ✅ 合意完了 |
| Red Team 通知の簡素化 | ✅ フラグベースは正しい判断 |

**100% 合意。追加で 2 点の確認を提出:**

#### Confirmation A: chronicle handoff は QG FAIL 時も更新すべき

QG が FAIL した場合でも、chronicle.yaml の handoff セクションは更新すべき。理由:

- FAIL 時こそ「何が失敗したか」「次に何をすべきか」の引き継ぎが重要
- コンパクションやリセットが発生した場合、handoff が古いままだと復帰が困難

```yaml
# QG FAIL 時の handoff 例
handoff:
  current_task: { id: 3, title: "API endpoint実装", status: "blocked" }
  done_in_this_session:
    - "POST /research endpoint 作成"
    - "テスト 3/5 通過"
  next_steps:
    - "残り2テストの修正"
    - "QG 再実行"
  blockers:
    - "vitest の型エラー: src/api/research.ts:45"
  qg_result: "FAIL"
  qg_failures:
    - "テスト 2 件失敗"
```

#### Confirmation B: Fix Agent に worktree パスを渡す

Cast が Git worktree（`/tmp/<slug>-<task-id>`）で作業している場合、Fix Agent にも同じ worktree パスを渡す必要がある。そうしないと Fix Agent がメインブランチのファイルを修正してしまう。

```
Task(
    prompt: """
    ## Fix Agent
    ### 作業ディレクトリ
    /tmp/giorno-T003   ← worktree パスを明示
    ...
    """
)
```

---

## 最終合意: Swarm v2 設計仕様

### 全合意項目一覧

| # | 論点 | 合意内容 | 提案者 |
|---|------|---------|--------|
| 1 | ファイル構成 | **1 ファイル**（SKILL.md）にセクションアノテーションで条件分岐 | Fugo |
| 2 | Phase 構成 | **5 Phase**（現行維持）。Design Debate の Phase 0 は追加しない | Fugo |
| 3 | Design Debate | Swarm スコープ外。Director 指示書で管理 | Fugo |
| 4 | フレームワーク QG | 7 項目（うち 1 項目は推奨） | Polnareff + Fugo |
| 5 | TDD 適用範囲 | 実行可能コードのみ TDD。Markdown/YAML は整合性チェックリスト | Fugo |
| 6 | CI 連携 | Orchestrator 直接実行が主。CI 結果は補助情報 | Fugo |
| 7 | activity.log | 3 エントリ（開始・QG結果・完了） | Fugo |
| 8 | Red Team 通知 | フラグベース（`red_team_review` / `red_team_requested`） | Polnareff |
| 9 | chronicle handoff | QG PASS/FAIL 両方で更新 | Fugo |
| 10 | Fix Agent | worktree パスを明示的に渡す | Fugo |
| 11 | セクション番号チェック | 連番チェックではなく重複チェックのみ | Fugo |

**合意率: 100%（全 11 項目）**

---

### 1. SKILL.md 構成（合意版）

```
---
name: swarm
description: Swarm Development。設計書を元にマルチエージェント並列開発を実行。
argument-hint: [設計書パス]
---

# Swarm Development

設計書: $ARGUMENTS

## 即座に実行すること
[既存と同じ]

## あなたの役割: Orchestrator（Architect）
[既存と同じ]

## Phase 1: タスク分析・構成決定
[既存と同じ + 以下を追加]
- フレームワーク開発かアプリ開発かを判定
  - 対象ファイルが主に .md/.yaml → フレームワーク開発
  - 対象ファイルが主に .ts/.js/.css → アプリ開発

## Phase 2: Developer Agent 並列起動 + 2段階レビュー
[既存と同じ + 以下を修正]

### 開発ルール
#### [共通]
- 既存コード確認（重複防止）
- 設計書に従う
- 自己レビュー

#### [アプリ開発のみ]
- TDD（テスト駆動開発）を強制

#### [フレームワーク開発のみ]
- 整合性チェックリスト:
  - 変更ルールが他セクションと矛盾していないか
  - 新規ファイルがファイル所有権マトリクスに追加されているか
  - コンパクション復帰手順が更新されているか
  - 新規ルールに違反する既存コードがないか（Grep で確認）

## Phase 3: 統合・完了処理
[既存と同じ + 以下を追加]
- CI 結果が queue/ci_results/ に存在すれば参照（補助情報）
- Orchestrator が直接ビルド・テストコマンドを実行（主たる証拠）

## Phase 4: Quality Gate（証拠ベース検証）

### [共通 QG 項目]
| 項目 | 検証内容 |
|------|---------|
| テスト/ビルド | コマンド実行 + 出力確認 |
| 設計書照合 | 要件と実装の 1:1 マッピング |

### [フレームワーク開発 QG 追加項目]
| # | 項目 | 検証内容 |
|---|------|---------|
| F1 | セクション番号重複 | CLAUDE.md 等のセクション番号に重複がないか |
| F2 | ファイル所有権マトリクス | 新規ファイルが Section 7 のテーブルに追加されているか |
| F3 | コンパクション復帰手順 | 新規ファイルが Section 12 の手順に含まれているか |
| F4 | 指示書クロスリファレンス | 変更した仕様を参照すべき指示書が更新されているか |
| F5 | forbidden_actions | 新規ロールに適切な禁止事項が定義されているか |
| F6 | 整合性チェックリスト全項目 | Developer Agent の自己チェック結果を再検証 |
| F7 | 人間可読性（推奨） | 変更後のドキュメントを通読して自然か確認（推奨、必須ではない） |

### [Cast 運用 QG 追加項目]
| # | 項目 | 検証内容 |
|---|------|---------|
| C1 | chronicle handoff | handoff セクションが更新されているか（PASS/FAIL 両方） |
| C2 | Red Team フラグ | red_team_review フラグがあれば report に red_team_requested を設定 |

## Phase 5: 最終報告
[既存と同じ + 以下を追加]

### [Cast 運用時の追加処理]
- chronicle.yaml の handoff セクションを更新（QG PASS/FAIL 両方）
- activity.log に 3 エントリ追記:
  1. progress: Swarm 開始（タスク概要）
  2. progress: QG 結果（PASS/FAIL + 理由）
  3. progress: Swarm 完了（作成ファイル概要）
- red_team_requested フラグがあれば report.yaml に記載

## エラー時の対応
[既存と同じ + 以下を修正]

### Fix Agent
- worktree パスを明示的に渡す（Cast が /tmp/<slug>-<task-id> で作業している場合）
```

---

### 2. chronicle handoff 仕様（合意版）

```yaml
# cast/members/<slug>/chronicle.yaml
# QG PASS 時
handoff:
  current_task: { id: 3, title: "API endpoint実装", status: "completed" }
  done_in_this_session:
    - "POST /research endpoint 完成"
    - "全テスト通過（5/5）"
  next_steps:
    - "次タスク待ち"
  blockers: []
  qg_result: "PASS"

# QG FAIL 時
handoff:
  current_task: { id: 3, title: "API endpoint実装", status: "blocked" }
  done_in_this_session:
    - "POST /research endpoint 作成"
    - "テスト 3/5 通過"
  next_steps:
    - "残り2テストの修正"
    - "QG 再実行"
  blockers:
    - "vitest の型エラー: src/api/research.ts:45"
  qg_result: "FAIL"
  qg_failures:
    - "テスト 2 件失敗"
```

---

### 3. activity.log エントリ仕様（合意版）

```
# Swarm 開始時
[timestamp] [slug] progress: Swarm開始 - [タスク概要]

# QG 完了時
[timestamp] [slug] progress: QG [PASS|FAIL] - [理由/サマリー]

# Swarm 完了時
[timestamp] [slug] progress: Swarm完了 - 作成ファイル [N]件
```

---

### 4. Red Team 通知フロー（合意版）

```
Director がタスク配布時:
  queue/tasks/<slug>.yaml に red_team_review: true を設定
      ↓
Cast が Swarm 実行:
  Phase 5 で red_team_review フラグを確認
      ↓
  report.yaml に red_team_requested: true を設定
      ↓
Director がレポート確認時:
  red_team_requested を見て abbacchio にレビューを依頼

Cast が自己判断で追加する場合:
  「このコードはセキュリティに影響する」と判断
      ↓
  report.yaml に red_team_requested: true を自主的に設定
```

Swarm 内に条件判定ロジックは持たない。フラグの受け渡しのみ。

---

### 5. Fix Agent worktree 対応（合意版）

```
Task(
    subagent_type: "general-purpose",
    description: "Fix Agent: [エラー概要]",
    prompt: """
    ## 役割: Fix Agent

    ### 作業ディレクトリ
    [worktree パス（例: /tmp/giorno-T003）]
    ※ このディレクトリで作業すること。メインブランチのファイルを変更しないこと。

    ### 検出されたエラー
    [エラーメッセージ全文]

    ### 発生箇所
    [ファイル:行番号]

    [以下既存と同じ]
    """
)
```

---

### 6. 整合性チェックリスト（フレームワーク開発用 TDD 代替）

```markdown
### フレームワーク整合性チェックリスト（Developer Agent 自己チェック）

- [ ] 変更したルールが他セクション・他ファイルと矛盾していないか
- [ ] 新規ファイルがファイル所有権マトリクス（CLAUDE.md Section 7）に追加されているか
- [ ] コンパクション復帰手順（CLAUDE.md Section 12）が更新されているか
- [ ] 新規ルールに違反する既存コード/設定がないか（Grep で確認）
- [ ] セクション番号に重複がないか
- [ ] 新規ロールに forbidden_actions が定義されているか（該当時のみ）
```

---

## メタ情報

| 項目 | 値 |
|------|-----|
| ディベート日 | 2026-02-09 |
| ラウンド数 | 2.5（Round 1 → Round 2 → Round 2.5 で合意） |
| 合意率 | 100%（全 11 項目） |
| Polnareff（Advocate） | Claude Opus 4.6 |
| Fugo（Challenger） | Claude Opus 4.6 |
| 参照ファイル | `.claude/skills/swarm/SKILL.md`, `docs/ensemble-v4-architecture.md`, `instructions/director.md`, `instructions/cast_template.md`, `CLAUDE.md` |

### 次のステップ

1. Owner が本設計を承認
2. `.claude/skills/swarm/SKILL.md` を本設計に基づいて改修
3. フレームワーク P1（衛生改善）で実際に使用して検証
