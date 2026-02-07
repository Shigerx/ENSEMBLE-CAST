# ENSEMBLE-CAST v3 — 大規模プロダクション設計書

> ステータス: 設計中
> 作成日: 2026-02-07
> 前提: v2 堅牢性アップグレード（実装済み）
> 目的: 10名超のAgentによる大規模開発を、映画制作メタファーで実現する
> 参照: plans/multi-team-architecture.md（初期構想）

---

## 思想: 「大作映画の現場」

小規模映画は1つのユニット（班）で撮影する。
大作映画は **複数ユニットが同時撮影** し、ラインプロデューサーが全体を統括する。

ENSEMBLE-CAST v3 は、この「大作映画の撮影現場」をそのまま開発に持ち込む。

```
小規模映画（v1-v2）:
  監督1人 + キャスト数名 + スクリプトスーパーバイザー1人

大作映画（v3）:
  エグゼクティブプロデューサー（EP）
    ↓
  ラインプロデューサー（LP）
    ├── 第一班: 監督 + キャスト + スクリプトスーパーバイザー
    ├── 第二班: 監督 + キャスト + スクリプトスーパーバイザー
    ├── VFX班: VFXスーパーバイザー + アーティスト
    └── 舞台監督（非LLM）: ロジスティクス・ルール強制
```

**群像劇は変わらない。舞台が大きくなるだけ。**

---

## 配役表（Role Mapping）

### メインキャスト（常駐ペイン）

| 映画の役職 | ENSEMBLE-CAST での名称 | 技術的な役割 | モデル |
|-----------|----------------------|------------|--------|
| エグゼクティブプロデューサー（EP） | Producer（既存を昇格） | PM: Owner対応、戦略判断 | Opus（thinking無効） |
| ラインプロデューサー（LP） | **Line Producer**（新設） | PL: クロスユニット調整、契約管理 | Opus（thinking有効） |
| 監督 | Director（既存、ユニット単位に） | Tech Lead: ユニット内タスク管理 | Sonnet（thinking有効） |
| キャスト | Cast（既存） | Developer: 実装 | Sonnet（thinking有効） |

### サブエージェント（オンデマンド召喚）

必要な時にDirectorまたはLPがTask toolで召喚し、YAML報告後に解散する。

| 映画の役職 | ENSEMBLE-CAST での名称 | 技術的な役割 | 召喚者 |
|-----------|----------------------|------------|--------|
| 助監督（AD） | **Assistant Director** | Director補佐: 大ユニット時にCast管理を分担 | Director |
| スクリプトスーパーバイザー | **Script Supervisor** | QA: ビルド・テスト・仕様準拠の検証 | Director |
| 撮影監督 | **Technical Advisor** | 影響調査・要件プッシュバック・技術判断 | LP / Director |
| ロケーションスカウト | **Location Scout** | 技術調査・ライブラリ選定・環境調査 | Director |
| 考証担当 | **Research Consultant** | キャラ/技術リサーチ・仕様の正確性検証 | Director |
| 脚本修繕 | **Script Doctor** | リファクタリング設計・コード構造の改善提案 | Director / LP |
| プリビズアーティスト | **Previs Artist** | PoC/プロトタイプ作成・技術検証 | Director / LP |
| 編集技師 | **Editor** | 統合整合性検証・複数ユニット成果物の結合 | LP |

### 非LLM（スクリプト常駐）

| 映画の役職 | ENSEMBLE-CAST での名称 | 技術的な役割 | 実装 |
|-----------|----------------------|------------|------|
| 舞台監督 | **Stage Manager** | ルーティング・ルール強制・状態管理 | Node.js スクリプト |

### 新設ロールの詳細

#### Line Producer（ラインプロデューサー）— メイン

映画では: 撮影現場の全体統括。予算・スケジュール・各班の調整を担う。監督の上に立つが、クリエイティブには口を出さない。

ENSEMBLE-CASTでは:
- **ユニット間の依存関係を管理**
- **コールシート（契約）の作成・変更管理**
- **各ユニットのDirectorからの報告を集約**
- Producer（EP）への報告窓口
- **コードは書かない。ユニット内の判断には介入しない。**

```
位置づけ:
  Producer（EP）→ Line Producer（LP）→ Director×N

  v2までのProducer→Director の関係を、LP→Director に移行。
  Producerは戦略に専念。LPが現場を見る。
```

### サブエージェント詳細

サブエージェントは **エピソード型ワークフロー** で動作する:
1. 召喚者（Director / LP）が Task tool で起動
2. 必要な調査・検証を実行
3. 結果を YAML で報告
4. 解散（ペインを占有しない）

#### Assistant Director（助監督）

映画では: 監督の右腕。エキストラの管理、スケジュール調整、セット準備を担う。

ENSEMBLE-CASTでは:
- **Director の認知負荷が高い時にオンデマンドで召喚**
- Cast の一部を AD に委任（例: Cast 6名 → Director 3名 + AD 3名）
- Director からの明示的な委任でのみ動作
- **ユニット内でしか権限を持たない**

```
通常（Cast 4名以下）:
  Director → Cast A, B, C, D

大ユニット（Cast 5名以上）:
  Director → Cast A, B, C
       ↓
  Assistant Director（サブ）→ Cast D, E, F
```

**召喚条件**: Director が自ユニットの Cast を5名以上管理する場合。

#### Script Supervisor（スクリプトスーパーバイザー）

映画では: 撮影中の整合性を記録する係。セリフの間違い、衣装の変化、シーンの繋がりを細かくチェックする。

ENSEMBLE-CASTでは（旧 Reviewer を昇格）:
- ビルド・テスト・仕様準拠を実際にコマンド実行して検証
- 問題があれば結果を YAML で Director に報告
- **コードは書かない。指摘のみ。**
- 指示書: `instructions/reviewer.md`（既存を活用）

```
フロー:
  Cast が作業完了 → Director が Script Supervisor を召喚
  → ビルド・テスト・仕様検証 → YAML報告 → 解散
```

**v2からの変遷**: 常駐ペインから召喚型に変更。Reviewが必要ない時間帯にペインを消費しない。

#### Technical Advisor（撮影監督 / テクニカルアドバイザー）

映画では: 撮影技法の専門家。カメラワーク・照明・構図の技術的判断を行い、監督の意図を技術的に実現可能な形にする。

ENSEMBLE-CASTでは:
- **新機能追加時の影響調査**（依存関係、既存コードへの影響）
- **要件に対するプッシュバック**（技術的に無理な要件への代案提示）
- **アーキテクチャ判断の助言**
- LP または Director が召喚

```
フロー:
  「機能Bを追加したい」→ TA召喚 → 影響調査レポート(YAML) → 解散
  → Director/LP がレポートを元に判断
```

#### Location Scout（ロケーションスカウト）

映画では: 撮影場所を探し、条件を調査して報告する。

ENSEMBLE-CASTでは:
- **ライブラリ・フレームワークの調査・選定**
- **既存環境の調査**（DBスキーマ、API仕様の把握）
- **技術スタックの比較レポート作成**

```
フロー:
  「認証にどのライブラリを使うか？」→ LS召喚
  → 候補調査・比較表(YAML) → 解散
```

#### Research Consultant（考証担当）

映画では: 時代考証・風俗考証・技術考証を担当。作品の正確性を裏付けるリサーチを行う。日本映画における「考証」の役割。

ENSEMBLE-CASTでは:
- **キャストのペルソナリサーチ**（キャラクター設定の調査・深掘り）
- **ドメイン知識の調査**（業界用語、規格、ベストプラクティス）
- **仕様の正確性検証**（技術仕様が現実と合っているか）

```
フロー:
  「このキャストの専門領域を調べて」→ RC召喚
  → リサーチ結果(YAML) → persona.yaml に反映 → 解散
```

#### Script Doctor（脚本修繕）

映画では: 問題のある脚本を修繕するために呼ばれる専門家。ハリウッドで実際に使われている役職名。構造的な問題を診断し、改善案を提示する。

ENSEMBLE-CASTでは:
- **リファクタリング設計**（コード構造の問題診断・改善提案）
- **技術的負債の分析**
- **コードは書かない。設計案のみ提示。**

```
フロー:
  「このモジュールの複雑度が高い」→ SD召喚
  → 構造分析 + リファクタリング計画(YAML) → 解散
  → Director が計画をタスクに分解 → Cast が実装
```

#### Previs Artist（プリビズアーティスト）

映画では: プリビジュアライゼーション担当。本番撮影前にシーンの3Dドラフトを作り、技術的に実現可能かを低コストで検証する。捨てる前提で作る。

ENSEMBLE-CASTでは:
- **PoC（概念実証）/ プロトタイプの作成**
- **技術的実現可能性の検証**
- **本番コードとは別に、使い捨ての検証コードを書く**

```
フロー:
  「WebSocketでリアルタイム通信できるか検証して」→ PA召喚
  → プロトタイプ作成 + 検証結果(YAML) → 解散
  → 結果を元に Go/No-Go 判断
```

#### Editor（編集技師）

映画では: 複数ユニットから上がってきたバラバラの素材を一つの作品に組み上げる。カット間の整合性、シーンのつながり、全体の流れを検証・調整する。

ENSEMBLE-CASTでは:
- **複数ユニットの成果物を統合する際の整合性検証**
- **コールシート契約とインテグレーションの一致確認**
- **ユニット間のインターフェース結合テスト**
- LP が召喚（ユニットをまたぐ検証のため）

```
フロー:
  ユニットA・Bの実装完了 → LP が Editor を召喚
  → 結合テスト実行 + 整合性チェック(YAML) → 解散
  → 問題があれば LP が関連 Director に通知
```

### 非LLMプロセス

#### Stage Manager（舞台監督）— 非LLMプロセス

映画では: リハーサルの進行、出入り管理、技術スタッフの調整。クリエイティブには関与しない裏方。

ENSEMBLE-CASTでは: **LLMではなく、Node.jsスクリプト**として動作する。

```
ensemble-stage-manager/
  ├── guard.js        # pre-commit hook: owned_files/branch 強制
  ├── router.js       # メッセージルーティング（将来のAgent Teams対応層）
  ├── checkpoint.js   # 各Agent停止時の状態保存
  └── health.js       # Agent生存確認・自動復帰
```

**なぜLLMでないか**: ルーティングとルール強制にLLMは不要。判断が不要な仕事にLLMを使うのはコストの無駄。舞台監督は「ルールを粛々と適用する」存在。

---

## ユニット構成（Unit System）

### ユニットの種類

映画制作にならい、プロジェクトの性質に応じてユニットを構成:

| ユニット種別 | 映画での役割 | 開発での役割 | 典型的な構成 |
|------------|------------|------------|------------|
| メインユニット（第一班） | メインの撮影 | コア機能開発 | Director + Cast×2-3 + QA |
| セカンドユニット（第二班） | アクション・風景 | サブ機能・ユーティリティ | Director + Cast×1-2 + QA |
| VFXユニット | 視覚効果 | インフラ・パフォーマンス | VFX Supervisor + Cast×1-2 |
| プリビズユニット | 事前検証・ロケテスト | 実験・プロトタイプ | Director + Cast×1 |

### ユニット定義

```yaml
# config/units.yaml（新規）
units:
  frontend:
    type: main_unit
    name: "第一班: フロントエンド"
    director: { slug: botan, model: sonnet }
    cast:
      - { slug: nene, role: dev }
      - { slug: polka, role: dev }
    domain: "src/components/, src/pages/, src/hooks/"

  backend:
    type: main_unit
    name: "第二班: バックエンド"
    director: { slug: danny, model: sonnet }
    cast:
      - { slug: rusty, role: dev }
      - { slug: linus, role: dev }
    domain: "src/api/, src/services/, src/db/"

  infra:
    type: vfx_unit
    name: "VFX班: インフラ"
    director: { slug: neo, model: sonnet }
    cast:
      - { slug: trinity, role: dev }
    domain: "infra/, docker/, ci/"

# サブエージェントはユニット定義に含めない。
# Director が必要に応じて Task tool で召喚する。
# 例: Script Supervisor, Technical Advisor, Location Scout 等

cross_unit:
  line_producer: { slug: spielberg, model: opus }
  producer: { slug: producer, model: opus }  # EP（既存）
```

### ドメイン境界

各ユニットは **domain（担当ディレクトリ）** を持つ。
- ユニット内の Cast は自ドメインのファイルのみ編集可能
- ドメイン外のファイルはコールシート（契約）で調整
- Stage Manager（guard.js）が commit 時にドメイン違反を reject

---

## コールシート（契約システム）

### 映画のコールシートとは

撮影日の「誰が、いつ、どこで、何をするか」を記した指示書。
全スタッフがこれを見て動く。

### ENSEMBLE-CAST でのコールシート

**ユニット間のインターフェース契約** として機能する。

```yaml
# contracts/frontend-backend-api.yaml（新規ディレクトリ）
call_sheet:
  id: CS-001
  title: "Todo API 契約"
  status: agreed  # draft → negotiation → agreed → implemented → verified

  provider:
    unit: backend
    director: danny
  consumer:
    unit: frontend
    director: botan

  # 契約内容
  interface:
    type: rest_api
    base_path: /api/todos
    endpoints:
      - method: GET
        path: /
        response: |
          { items: Todo[], total: number }
      - method: POST
        path: /
        request: |
          { title: string, due_date?: string }
        response: |
          { id: string, ...Todo }

    shared_types:
      file: "contracts/types/todo.ts"
      types:
        - name: Todo
          definition: |
            { id: string; title: string; done: boolean; due_date: string | null; }

  # 変更履歴
  changelog:
    - version: 1
      date: 2026-02-07
      author: spielberg  # LP が初版作成
      changes: "初版作成"

  # 検証方法
  verification:
    method: contract_test
    test_file: "tests/contracts/frontend-backend.test.ts"
```

### コールシートの運用フロー

```
1. LP がプロジェクト分析時にコールシートのドラフトを作成
   status: draft

2. 関連ユニットの Director が内容をレビュー
   Director → LP に修正提案（negotiation）
   status: negotiation

3. 全 Director が合意
   status: agreed

4. 各ユニットが契約に基づいて実装
   status: implementing

5. 契約テストが通過
   status: verified
```

### コールシート変更プロトコル（ユニット間交渉）

開発中に契約変更が必要になった場合:

```
Cast が「API のレスポンス形式を変えたい」と発見
  ↓
Cast → Director に報告（report.yaml に change_request）
  ↓
Director → LP に変更リクエスト（contracts/requests/CR-001.yaml）
  ↓
LP が影響範囲を分析（どのユニットに影響するか）
  ↓
LP → 関連 Director 全員に通知（交渉開始）
  ↓
Director 同士が LP を介して交渉
  ├── 合意 → コールシート更新 → 各ユニットに反映指示
  └── 不合意 → LP が調停案を提示 → 再交渉 or EP にエスカレーション
```

**これが「交渉で開発が進む」の実現形。** Director 同士の群像劇が生まれる。

---

## 通信アーキテクチャ

### 3層通信モデル

```
Layer 1: ユニット内通信（Intra-Unit）
  Director ↔ Cast, Director ↔ Reviewer
  → 既存の ENSEMBLE-CAST v2 プロトコルをそのまま使用
  → send-keys + YAML（将来 Agent Teams に差し替え可能）

Layer 2: ユニット間通信（Inter-Unit）
  Director ↔ LP ↔ Director
  → コールシート + メッセージキュー
  → Stage Manager（router.js）がルーティング

Layer 3: 戦略通信（Strategic）
  LP ↔ Producer（EP）↔ Owner
  → dashboard.md + send-keys（既存）
```

### Layer 2: メッセージキュー（新設）

```yaml
# queue/inter_unit/to-frontend-director.yaml
messages:
  - id: IU-001
    from: { role: line_producer, slug: spielberg }
    to: { role: director, slug: botan, unit: frontend }
    type: contract_change
    payload:
      call_sheet_id: CS-001
      change: "Todo型に priority フィールド追加"
      impact: "TodoList コンポーネントの表示変更が必要"
    timestamp: 2026-02-07T15:30:00
    status: unread  # unread → read → acknowledged → resolved
```

### 通信の抽象化レイヤー

```
現在の通信手段:
  tmux send-keys（脆弱だが動く）

将来の通信手段:
  Agent Teams API（安定したら）

抽象化:
  scripts/send-message.sh <target> <message>
    → 内部で tmux send-keys OR Agent Teams API を呼ぶ
    → 上位ロジックは通信手段を意識しない
```

`scripts/send-message.sh` が通信バックエンドを隠蔽。Agent Teams が安定した時点で、このスクリプトの中身だけ差し替えれば全体が移行完了。

---

## Stage Manager（舞台監督）詳細設計

### 概要

**非LLMの Node.js プロセス群**。映画の舞台監督のように、裏方でロジスティクスを処理する。

### コンポーネント

#### 1. guard.js — ルール強制（pre-commit hook）

```javascript
// git pre-commit hook として動作
// 以下をプログラム的に検証:

// 1. ブランチ名チェック
//    cast/<slug>/<task-id>-* 形式でなければ reject

// 2. ファイルオーナーシップチェック
//    file_registry.yaml の owned_files 外の変更を reject

// 3. ドメイン境界チェック
//    units.yaml の domain 外のファイル変更を reject

// 4. コールシート型チェック（将来）
//    contracts/ の型定義と実装の整合性を検証
```

#### 2. router.js — メッセージルーティング

```javascript
// queue/inter_unit/ のファイル変更を監視（chokidar）
// 新しいメッセージを検知したら:
//   1. 宛先の Agent の pane_id を config/panes.yaml から取得
//   2. Busy/Idle チェック
//   3. send-keys で起床（将来: Agent Teams API）
//
// これにより LP や Director が直接 send-keys を管理する必要がなくなる
// メッセージを YAML に書くだけで、ルーティングは Stage Manager が行う
```

#### 3. checkpoint.js — 状態スナップショット

```javascript
// 各 Agent の停止を検知したら（pane の出力監視）:
//   1. 現在のタスク状態を収集
//   2. checkpoints/<slug>.yaml に保存
//
// コンパクション復帰が 10ステップ → 2ステップに:
//   1. checkpoints/<slug>.yaml を読む
//   2. 作業再開
```

```yaml
# checkpoints/botan.yaml（自動生成）
checkpoint:
  slug: botan
  role: director
  unit: frontend
  current_task:
    id: 5
    title: "TodoList コンポーネント実装"
    status: reviewing
  pending_decisions: []
  last_action: "Cast nene の完了報告を受信、レビュー開始"
  next_action: "レビュー結果を判定し、approved/rejected を決定"
  context_files:
    - queue/tasks/nene.yaml
    - queue/reports/nene_report.yaml
  timestamp: 2026-02-07T16:45:00
```

#### 4. health.js — 生存監視

```javascript
// 各 Agent ペインを定期チェック（30秒間隔）
// 異常検知:
//   - ペインが消えている → LP に通知
//   - 長時間 Busy（10分以上） → LP に通知
//   - エラーメッセージ検出 → LP に通知
//
// 自動復帰:
//   - ペイン消失 → 再作成 + checkpoint から復帰指示
```

### Stage Manager の起動

```bash
# launch-ensemble.sh に追加
# Stage Manager は tmux の別ペインで常駐
node scripts/stage-manager/guard.js &
node scripts/stage-manager/router.js &
node scripts/stage-manager/checkpoint.js &
node scripts/stage-manager/health.js &
```

---

## デイリーラッシュ（進捗レビュー）

### 映画のデイリーラッシュとは

その日撮影したフィルムを関係者で確認する儀式。
問題の早期発見と方向修正に使われる。

### ENSEMBLE-CAST でのデイリーラッシュ

**LP が定期的（全ユニットの1ラウンド完了時）に生成する統合レポート。**

```markdown
# dailies/2026-02-07-round1.md（自動生成）

## デイリーラッシュ — Round 1

### ユニット状況
| ユニット | Director | タスク進捗 | ブロッカー |
|---------|----------|-----------|-----------|
| 第一班(FE) | botan | 3/5 完了 | なし |
| 第二班(BE) | danny | 2/4 完了 | DB設計待ち |
| VFX班(Infra) | neo | 1/2 完了 | なし |

### コールシート状況
| 契約 | Provider → Consumer | Status |
|------|-------------------|--------|
| CS-001 Todo API | BE → FE | implementing |
| CS-002 Auth API | BE → FE | agreed |

### 変更リクエスト
| CR | 内容 | 影響ユニット | 状態 |
|----|------|------------|------|
| CR-001 | Todo に priority 追加 | FE, BE | 交渉中 |

### 🚨 エスカレーション
- BE班: DB設計の技術選定で判断が必要（PostgreSQL vs SQLite）

### 📊 全体進捗
- 総タスク: 11
- 完了(approved): 6 (54.5%)
- 進行中: 3
- ペンディング: 1
- ブロック: 1
```

---

## 階層構造（v3 完全版）

```
Owner（人間・上様）
  ↓ 対話                    ↑ デイリーラッシュ + dashboard.md
┌──────────────────────┐
│  PRODUCER（EP）       │ ← 戦略統括・Owner対応
│  エグゼクティブプロデューサー │
└──────────┬───────────┘
           ↓ 方針指示         ↑ 統合レポート
┌──────────────────────┐
│  LINE PRODUCER（LP）  │ ← 現場統括・ユニット間調整・契約管理
│  ラインプロデューサー      │
└──────────┬───────────┘
           ↓ コールシート + タスク  ↑ ユニットレポート
     ┌─────┼─────────────┐
     ▼     ▼             ▼
┌─────────┐ ┌─────────┐ ┌─────────┐
│ Unit A  │ │ Unit B  │ │ Unit C  │
│ 第一班   │ │ 第二班   │ │ VFX班   │
│         │ │         │ │         │
│ Director│ │ Director│ │ Director│
│ Cast×2  │ │ Cast×2  │ │ Cast×1  │
└─────────┘ └─────────┘ └─────────┘

サブエージェント（オンデマンド召喚・YAML報告後に解散）:
┌──────────────────────────────────────────────────────┐
│ Script Supervisor  Technical Advisor  Location Scout  │
│ Assistant Director  Research Consultant  Editor       │
│ Script Doctor  Previs Artist                         │
└──────────────────────────────────────────────────────┘

横断（非LLM常駐プロセス）:
┌──────────────────────────────────────────────────────┐
│  STAGE MANAGER                                       │
│  guard.js | router.js | checkpoint.js | health.js    │
└──────────────────────────────────────────────────────┘
```

---

## ファイル構造（v3）

```
ENSEMBLE-CAST/
├── CLAUDE.md                      # 全Agent共通ルール（v3更新）
├── instructions/
│   ├── producer.md                # EP指示書（v3更新）
│   ├── line_producer.md           # LP指示書（新規）
│   ├── director.md                # Director指示書（v3更新: ユニット対応）
│   ├── cast_template.md           # Cast指示書（v3更新）
│   └── reviewer.md                # Script Supervisor指示書（既存を活用）
│
├── config/
│   ├── panes.yaml                 # ペインID（既存）
│   ├── production.yaml            # プロジェクト設定（既存）
│   └── units.yaml                 # ユニット構成（新規）
│
├── contracts/                     # コールシート（新規ディレクトリ）
│   ├── CS-001-todo-api.yaml       # ユニット間契約
│   ├── CS-002-auth-api.yaml
│   ├── requests/                  # 変更リクエスト
│   │   └── CR-001.yaml
│   └── types/                     # 共有型定義
│       └── todo.ts
│
├── cast/                          # 既存構造を維持
│   ├── roster.yaml
│   └── members/
│       └── <slug>/
│           ├── persona.yaml
│           ├── chronicle.yaml
│           └── relationships.yaml
│
├── queue/
│   ├── producer_to_lp.yaml        # EP → LP（新規、旧 producer_to_director.yaml）
│   ├── lp_to_units/               # LP → 各ユニット（新規）
│   │   ├── frontend.yaml
│   │   └── backend.yaml
│   ├── inter_unit/                # ユニット間メッセージ（新規）
│   │   ├── to-frontend-director.yaml
│   │   └── to-backend-director.yaml
│   ├── tasks/<slug>.yaml          # 既存
│   ├── reports/<slug>_report.yaml # 既存
│   ├── pending_tasks.yaml         # v2
│   └── file_registry.yaml         # v2
│
├── checkpoints/                   # 状態スナップショット（新規）
│   └── <slug>.yaml
│
├── dailies/                       # デイリーラッシュ（新規）
│   └── <date>-round<N>.md
│
├── dashboard.md                   # 既存（LP が更新に変更）
│
├── scripts/
│   ├── launch-ensemble.sh         # 起動スクリプト（v3更新）
│   ├── wake-agent.sh              # 既存
│   ├── add-cast-pane.sh           # 既存
│   ├── send-message.sh            # 通信抽象化レイヤー（新規）
│   └── stage-manager/             # 舞台監督プロセス群（新規）
│       ├── guard.js
│       ├── router.js
│       ├── checkpoint.js
│       └── health.js
│
└── plans/                         # 設計書
    ├── v2-robustness-upgrade.md
    ├── v3-large-scale-production.md  # 本文書
    └── multi-team-architecture.md    # 初期構想
```

---

## 群像劇の深化: ユニット間の物語

v3 の真の価値は **ユニット間の交渉が群像劇を生む** こと。

### シナリオ例

```
第一班 Director（ぼたん）:
  「APIレスポンスに created_at が欲しい。コールシート変更を申請する。」

第二班 Director（ダニー）:
  「created_at の追加はDB変更が伴う。今のスプリントでは厳しい。
   次のラウンドに回せないか？」

LP（スピルバーグ）:
  「第一班はソート機能で created_at が必須。
   提案: 第二班は created_at を DB から返すだけ。
   ソートロジックはフロントに任せる。これなら変更は最小限。」

ぼたん: 「了解。フロントでソートする。」
ダニー: 「それなら対応可能。次のタスクに含める。」

LP: 「合意。コールシート CS-001 v2 を更新する。」
```

**キャラクターの個性が交渉スタイルに反映される。**
慎重なキャラは影響範囲を先に確認し、大胆なキャラは即決する。
これが ENSEMBLE-CAST の群像劇。

---

## 実装ロードマップ

### v2.1 — Stage Manager: guard.js（ルール強制）

**コスト: 数時間 | 効果: 高**

- `scripts/stage-manager/guard.js` 作成
- git pre-commit hook で owned_files / branch / domain を検証
- **LLMの「お願い」→ プログラムの「強制」に転換**

影響ファイル:
- `scripts/stage-manager/guard.js`（新規）
- `.githooks/pre-commit`（新規）

### v2.5 — 通信抽象化 + チェックポイント

**コスト: 1日 | 効果: 中**

- `scripts/send-message.sh` で通信手段を抽象化
- `scripts/stage-manager/checkpoint.js` でコンパクション耐性向上
- 既存の send-keys 呼び出しを send-message.sh に段階的に移行

影響ファイル:
- `scripts/send-message.sh`（新規）
- `scripts/stage-manager/checkpoint.js`（新規）
- `checkpoints/`（新規ディレクトリ）
- 各指示書の send-keys 部分を send-message.sh に書き換え

### v3.0 — マルチユニット + コールシート

**コスト: 2-3日 | 効果: 大（大規模対応の本命）**

- `config/units.yaml` でユニット構成を定義
- `contracts/` ディレクトリでコールシート管理
- `instructions/line_producer.md` LP指示書作成
- `instructions/assistant_director.md` AD指示書作成
- `queue/inter_unit/` ユニット間メッセージキュー
- `dailies/` デイリーラッシュレポート
- `scripts/stage-manager/router.js` メッセージルーティング
- 既存指示書のv3対応更新（CLAUDE.md, director.md, cast_template.md, reviewer.md, producer.md）

影響ファイル: 多数（全指示書 + 新規ファイル群）

### v3.5 — Stage Manager: health.js（自動復帰）

**コスト: 1日 | 効果: 中**

- `scripts/stage-manager/health.js` でAgent生存監視
- ペイン消失時の自動再作成 + checkpoint 復帰
- LP への異常通知

### v4.0 — Agent Teams 統合

**コスト: Agent Teams 安定待ち | 効果: 通信基盤の根本改善**

- `scripts/send-message.sh` の内部を Agent Teams API に差し替え
- tmux send-keys を廃止（ただし視覚モニタリング用に tmux は残す）
- ユニット内通信: Agent Teams の Task tool
- ユニット間通信: Agent Teams + コールシートYAML

**v2.5 で通信を抽象化しているので、移行は send-message.sh の中身だけ。**

---

## v2 からの移行パス

### 既存プロジェクト（小〜中規模）への影響

**v3 はオプトイン。既存の v2 プロジェクトはそのまま動く。**

```yaml
# config/production.yaml
scale: small    # small: v2モード（Director 1人）
                # large: v3モード（マルチユニット）
```

- `scale: small` → 従来通り Producer → Director → Cast
- `scale: large` → Producer → LP → Director×N → Cast

### 段階的導入

```
既存プロジェクト（v2）
  ↓ units.yaml を追加
  ↓ LP を起動
  ↓ Director を複数に分割
v3 マルチユニットモード
```

---

## コスト試算

### 小規模（v2モード: Cast 4名）
- 常駐: Producer(Opus) + Director(Sonnet) + Cast×4(Sonnet) = 6 Agent
- サブ: Script Supervisor 等はオンデマンド（必要な時だけコスト発生）
- Stage Manager: LLMコスト 0（スクリプト）
- 推定: $5-15/セッション

### 大規模（v3モード: Cast 8名 + ユニット3つ）
- 常駐: Producer(Opus) + LP(Opus) + Director×3(Sonnet) + Cast×6(Sonnet) = 11 Agent
- サブ: Script Supervisor, Technical Advisor, Editor 等はオンデマンド
- Stage Manager: LLMコスト 0
- 推定: $15-40/セッション
- **ただし**: ユニット分離により各 Agent のコンテキスト使用量が減少 → 実質コストは線形増加しない
- **サブエージェント化の効果**: 常駐 13 → 11 に削減。レビュー待ちの空きペインが無くなる

### コスト削減ポイント
1. Stage Manager が LLM 不要（最大のコスト削減）
2. サブエージェント化で常駐ペイン削減（レビュー待ちの空きペイン解消）
3. モデルティアリング（Opus は EP/LP のみ、他は Sonnet）
4. ユニット分離によるコンテキスト効率化
5. checkpoint による無駄な再読み込み削減

---

## 設計原則

1. **群像劇を殺さない**: 全ての新機能がキャラクターの交流を生む形で設計する
2. **追記ベース**: 既存の指示書を壊さない。v2 の上に v3 を積む
3. **オプトイン**: 小規模プロジェクトは v2 のまま使える
4. **非LLMで済むことにLLMを使わない**: Stage Manager は徹底的にスクリプト
5. **通信を抽象化**: Agent Teams 移行を見据えて、通信手段をハードコードしない
6. **映画メタファーに忠実**: 新しい概念は必ず映画制作の役職・用語にマッピングする

---

## 注意事項

- v3.0 の実装前に v2.1（guard.js）で「プログラム的強制」の価値を検証すること
- LP の指示書は Director 指示書をベースに、ユニット間調整の責務を追加する形で作成
- Agent Teams の Windows 安定性（#23435）を継続ウォッチ
- 初回の v3.0 テストは 2ユニット構成で実施（plans/multi-team-architecture.md の Phase 1 に合わせる）
