# ENSEMBLE-CAST v4 アーキテクチャ設計 — クロスAIディベート

> **起点**: 2つのX投稿がこの設計議論のきっかけ
> - [篠塚モデル](https://x.com/shinojapan/status/2019620314867724681) — 令和トラベルCEO。Claude Agent Teams で11体AIチームを運用。Red Team が直接他Agentにフィードバックし修正サイクルが回る
> - [Carliniモデル](https://x.com/__SatoshiSsSs__/status/2020145601678303607) — Anthropic研究者。16体のClaude Codeを並列で走らせCコンパイラを構築。オーケストレーター不要、Git協調、while trueループ、$20K/2週間

---

## 現状の課題（合意済み）

1. **Director がボトルネック**: Cast間の全通信がDirector経由の伝言ゲーム
2. **並列化の旨味が出ていない**: 各Castは振られた仕事をやって報告するだけ。議論・調整不可
3. **Red Team / Review が常設でない**: 独立した批判的視点がない
4. **チームが学習しない**: 個人記録のみ。チームノウハウ蓄積なし
5. **CI/CD がない**: テスト自動検証なし
6. **Context Window 汚染**: テスト出力がコンテキストに流れ込む

---

## Position A（Claude Opus — このファイルの起草者）

### 1. アーキテクチャ: ハイブリッド自律モデル

**核心**: tmux を可視化レイヤーとして残し、通信基盤を Agent Teams に移行。Cast間の直接通信を解禁。

```
Owner/Producer（人間）
  ↓ 直接指示（tmuxペインで対話）
Director（テックリード）
  ↓ タスクプール作成（TaskCreate）
┌─────────────────────────────────────────┐
│  Cast ←→ Cast（SendMessage で直接対話）  │
│  giorno ←→ bucciarati ←→ narancia      │
│       ←→ mista                          │
│                                          │
│  abbacchio（Red Team）                   │
│    → 全員のコードを読んで批判的レビュー   │
│    → Cast に直接「その前提正しい？」      │
│                                          │
│  共有: TaskList + Git repo               │
│  検証: CI自動テスト + Red Teamレビュー    │
└─────────────────────────────────────────┘
```

**Director の役割変更: 「全通信ハブ」→「テックリード」**
- タスクプール設計とアーキテクチャ判断に専念
- 個々のタスク配布・レビューの負荷から解放
- Cast は TaskList から自律的にタスク取得

**通信レイヤーの分離**:
- Layer 0: tmux = 可視化専用（Control Room / Theater UI のため）
- Layer 1: Agent Teams SendMessage = Cast間・Director間の通信
- Layer 2: Git = コードの同期と永続化
- Layer 3: CI (Node.js) = 自動検証（非LLM、コスト0）

**Agent Teams 選択の理由**:
- SendMessage でCast間直接DMが可能（篠塚モデルの核心）
- 共有TaskListでセルフサーブ（Carliniモデルの自律性）
- idle時に自動wake（ポーリング禁止と整合）
- tmux send-keys の不安定さ（2コールルール、Enter不達問題）を根本解決

**既存資産の活用**:
- `scripts/send-message.sh` は既に BACKEND 変数で切替対応。中身を Agent Teams API に差し替え可能
- tmux ペインは残す → Control Room / Theater UI が壊れない
- config/panes.yaml も残す → 可視化のため

### 2. Red Team: abbacchio 昇格

abbacchio の Moody Blues（過去再現能力）= forensic review にテーマ的に完璧。

**Red Team の権限**:
- 全Cast のコード読み取り
- 任意の Cast/Director に直接DM（「その前提正しい？」）
- CI 結果を見て「このマージはブロック」と判断
- dashboard.md の "Red Team Findings" に直接記入

**Red Team の禁止**:
- 自分でコードを書かない
- タスクの配布・変更はできない
- Cast に修正を命令できない（提案のみ）

### 3. 知識蓄積: Team Memory + Phase蒸留

```
memory/team_knowledge/
  patterns.yaml        # 再利用可能パターン
  anti_patterns.yaml   # 失敗パターン（地雷帳）
  decisions.yaml       # 技術判断と理由
  retrospective.yaml   # 振り返り
```

**学習ループ**: Phase完了時に蒸留スクリプトが知見を抽出 → 次Phase開始時にCastが読み込み

### 4. CI/CD: Carlini式自動検証

```
scripts/stage-manager/ci.js（新規）
  - post-commit hook でトリガー
  - worktree で隔離環境作成
  - build + test 実行
  - 結果をYAMLサマリー（5行）で配信
  - 全ログは logs/ci/ に保存
  - Cast のコンテキストを汚染しない
```

### 5. Context Window 汚染対策

- Cast のセルフチェック: 出力をファイルリダイレクト、サマリーのみ report
- CI が検証を代行（Cast が直接 npm test しない）
- Cast間メッセージ: 要約必須（フルログ禁止）
- テスト: `--fast` 的なサンプル実行（全テスト毎回はやらない）

### 6. コスト最適化

| ロール | モデル | 理由 |
|--------|--------|------|
| Director | Sonnet (default) | タスク設計・アーキ判断 |
| Cast (実装) | Sonnet (default) | コード品質が必要 |
| Red Team | Sonnet (default) | 批判的思考が必要 |
| 蒸留・分類 | Haiku (Task tool) | 定型作業。明確にテンプレ化できるものだけ |
| CI / health | Node.js (非LLM) | 判断不要な検証にLLM使うのは無駄 |

**Haiku利用方針**: モデル切替の仕組み自体は Task tool の `model: "haiku"` パラメータで既に簡単。ただし Cast の実装作業やレビューには使わない。定型作業（ログ分類、フォーマット検証等）のみ。

### 7. 段階的導入計画

| Phase | 内容 | Agent Teams依存 | 期間 |
|-------|------|----------------|------|
| A | CI + Context汚染対策 + Progress File | なし | 1-2日 |
| B | Team Memory + Phase蒸留 | なし | 1日 |
| C | Agent Teams 通信統合 + Cast間直接対話 | あり | 2-3日 |
| D | Red Team 常設（abbacchio昇格） | あり | 1-2日 |
| E | セルフサーブタスク管理 | あり | 1-2日 |

Phase A, B は今すぐ着手可能（Agent Teams 非依存）。
Phase C 以降は Agent Teams の WSL2 安定性を検証してから。

### 8. 変更対象ファイル一覧

**変更**:
- `CLAUDE.md` — 通信モデル、ファイル所有権、Red Teamルール、セルフサーブルール追加
- `instructions/director.md` — タスク「配布」→「プール作成」、Red Team委譲
- `instructions/cast_template.md` — 直接通信解禁、セルフサーブ、CI結果受信、team_knowledge読込
- `instructions/producer.md` — Owner直接運用への対応
- `instructions/reviewer.md` — Red Teamとの役割分担
- `scripts/send-message.sh` — Agent Teams バックエンド追加
- `launch-ensemble.sh` — Agent Teams モード、Red Team、CI/health起動
- `config/production.yaml` — communication_mode, red_team セクション追加

**新規**:
- `instructions/red_team.md` — Red Team専用指示書
- `scripts/stage-manager/ci.js` — 自動テスト実行
- `scripts/stage-manager/health.js` — Agent生存監視
- `scripts/distill-phase.sh` — Phase蒸留
- `.githooks/post-commit` — CIトリガー
- `memory/team_knowledge/*.yaml` — チーム知識層
- `progress/<slug>.yaml` — 復帰用進捗ファイル

---

## Position B（Claude Opus 4.6 — 別ターミナル、同一コードベース精読済み）

### 総評

Position A の方向性（Director薄体化、Red Team常設、知識蓄積、CI自動化）には**概ね賛同**する。
ただし **通信レイヤーの設計に致命的な技術誤認がある**。そこを正さないと Phase C 以降が全部崩壊する。

以下、6観点で具体的に指摘する。

---

### 1. アーキテクチャの問題点: Agent Teams とtmux Cast は共存不可能

**Position A の主張**: 「Layer 1: Agent Teams SendMessage = Cast間・Director間の通信」

**反論**: これは技術的に成立しない。

Agent Teams（`TeamCreate` / `SendMessage` / `TaskList`）は **1つのClaude Codeセッション内のサブエージェント間通信** である。

ENSEMBLE-CASTのCastは **独立したtmuxペインで動く別プロセスのClaude Code**。

```
現実の構造:
  tmux pane %0: Claude Code (Producer)   ← 独立プロセス
  tmux pane %1: Claude Code (Director)   ← 独立プロセス
  tmux pane %2: Claude Code (giorno)     ← 独立プロセス
  tmux pane %3: Claude Code (bucciarati) ← 独立プロセス

  これらは互いのAgent Teams APIにアクセスできない。
  SendMessage は同一セッション内のサブエージェント宛にしか送れない。
```

**Position A が成立するには以下のどちらかが必要**:

A) **tmuxを完全廃止し、1つのClaude Codeから全Castをサブエージェント（Task tool）で起動する**
   → ペルソナの永続性が死ぬ（サブエージェント終了 = コンテキスト消滅）
   → Control Room / Theater の LIVE モニタリングが不可能に
   → 「映画撮影」コンセプトの完全喪失

B) **Agent Teams にクロスプロセス通信機能が追加される**
   → 現時点で存在しない。Research Preview の今後のロードマップも不明
   → これに賭けて設計するのは危険

**Position A の「scripts/send-message.sh のバックエンドを Agent Teams に差し替え」も成立しない**。
send-message.sh は bash スクリプトであり、Claude Code の内部API（SendMessage tool）をbashから呼ぶ手段はない。

→ **結論: 通信レイヤーの設計を Agent Teams 非依存で再構築すべき。**

---

### 2. Agent Teams への依存リスク

Position A は Phase C〜E を Agent Teams に依存させている。リスク:

| リスク | 影響 | 発生確率 |
|--------|------|----------|
| Research Preview が廃止/大幅変更 | Phase C〜E 全滅 | 中（Anthropicは頻繁にAPI変更する） |
| WSL2 での Agent Teams 動作不良 | Chrome拡張 Issue #23082 の二の舞 | 高（WSL+Claude Code の実績が悪い） |
| Agent Teams のレートリミット追加 | 5体同時通信がスロットル | 中 |
| サブエージェントのコンテキスト上限 | 長時間タスクでサブエージェントが品質劣化 | 高 |

**Position A は Phase A, B を「Agent Teams非依存」としているが、Phase C 以降が全体の60%を占める。**
Agent Teams が使えなかった場合のフォールバックが設計されていない。

→ **提案: Agent Teams を「あったら嬉しいオプション」に留め、コア設計はファイルベース通信で完結させる。**

---

### 3. コスト見積りの妥当性

Position A のモデル選択テーブルは概ね合理的。ただし以下を補足:

**Maxプラン（$300/月）の場合**:
- トークン課金ではないので、Haiku にしてもコスト削減にならない
- Haiku のメリットは **レスポンス速度向上** と **レートリミット消費軽減** のみ
- Position A の「コスト最適化」セクションは API 直接課金前提で書かれている印象がある

**レートリミットの現実的制約**:
- 5 Cast + Director + Producer = 7プロセスが同時にAPIを叩く
- Maxプランのレートリミットは公開されていないが、同時7セッション×頻繁なリクエストは確実に衝突する
- Cast間直接通信を解禁すると通信量が増え、レートリミットがさらに厳しくなる

→ **提案: 「Cast間通信は非同期ファイルベース」にすることでAPI呼び出し回数を抑制。Cast は send-keys で起こされた時だけ動く（現行のイベント駆動を維持）。**

---

### 4. 段階的導入計画の問題

Position A の Phase 計画:
- Phase A, B: 良い。即着手可能。合意。
- Phase C: **技術的に成立しない**（上記1.で指摘）
- Phase D, E: Phase C に依存 → 連鎖的にブロック

**代替計画を提案する（Agent Teams 非依存版）**:

| Phase | 内容 | 依存 | 期間 |
|-------|------|------|------|
| **P1: 衛生改善** | Context汚染対策 + Progress File導入 + テスト出力サマリー化 | なし | 1日 |
| **P2: CI基盤** | `scripts/stage-manager/ci.js` + post-commit hook + ログ分離 | P1 | 1-2日 |
| **P3: Red Team昇格** | abbacchio昇格 + `instructions/red_team.md` + 全ブランチ閲覧権 + Cast直接send-keys権 | P2（CIでレビュー支援） | 1日 |
| **P4: Cast間技術掲示板** | `queue/discussion/<topic>.yaml` + ルール追加 + send-keysによるピアnotify | P3 | 1-2日 |
| **P5: Director薄体化** | タスクプール方式 + Cast自律取得（ファイルベース） + Directorをマージ/統合専任に | P4 | 2日 |
| **P6: Team Memory** | `memory/team_knowledge/` + Phase蒸留スクリプト + レトロスペクティブAgent | P5 | 1-2日 |

**P1〜P6は全てAgent Teams非依存。** 各Phaseで実際にプロダクション（F.L.A.R.E.）を回して検証可能。

Agent Teams が安定したら「P7: Agent Teams統合（オプション）」として検討する。
P7がなくても P1〜P6 で目標の80%は達成可能。

---

### 5. 見落としている課題

#### 5-A: Cast間通信のカオス制御

Position A は「Cast間直接DM」を解禁するが、**制御ルールが不足している**。

5体のCastが自由にDMし合うと:
- 全員のコンテキストが他者のメッセージで汚染される
- 「ABの会話 → Bの判断変更 → BがCに影響 → カスケード」が起きる
- Director が全体状況を把握できなくなる

**具体的ルール案**:
```yaml
# Cast間通信ルール（CLAUDE.md に追記）
cast_communication:
  allowed_topics:
    - api_interface      # 「このAPIの引数は？」「この型の定義は？」
    - shared_dependency  # 「このライブラリのバージョンは？」
    - blocked_by_peer    # 「Bの成果物がないと進めない」
  prohibited_topics:
    - task_reassignment  # 「これお前やってよ」→ Director経由
    - architecture       # 設計判断 → Director 判断
    - review_request     # レビュー → Red Team(abbacchio) or Director
  format:
    max_length: 500 chars  # 長文禁止。長いならファイルに書いてパス参照
    must_cc_director: true  # Directorのdiscussion logに自動記録
  mechanism: "queue/discussion/<topic>.yaml に追記 + send-keys で相手を起床"
```

#### 5-B: マージフロー

Position A の「セルフサーブタスク管理」で**マージ判断を誰がするか**が明示されていない。

Carliniモデルではマージは各Agentがpush/pullで解決する。
だが Web開発では UI/API/DB の結合が密結合で、テストだけでは検証しきれない統合問題がある。

**提案**: マージ権限はDirector専任で維持。理由:
- ファイル競合の判断には全体設計の把握が必要
- CI がパスしても機能統合テスト（E2Eテスト）がない初期には人間的判断が要る
- abbacchio（Red Team）がマージ前レビュー → Director がマージ実行、の二段階

#### 5-C: 復帰フローの一貫性

Position A は `progress/<slug>.yaml` を新設するが、既存の `chronicle.yaml` との役割分担が不明確。

**提案: chronicle.yaml を2セクション構成にする**（新ファイル不要）:
```yaml
# cast/members/<slug>/chronicle.yaml
# Section 1: 引き継ぎ情報（次の自分への手紙）— Carlini式progress
handoff:
  current_task: { id: 3, title: "API endpoint実装", status: "in_progress" }
  done_in_this_session:
    - "POST /research endpoint 完成"
    - "D1 テーブル作成済み"
  next_steps:
    - "GET /research/:id を実装する"
    - "エラーハンドリングを追加"
  blockers: []
  files_i_own:
    - "src/api/research.ts"
    - "src/db/schema.sql"

# Section 2: 累積記録（従来のchronicle）
entries:
  - id: 1
    task_id: 1
    action: "..."
    ...
```

#### 5-D: テスト戦略の欠如

CI自動検証を入れるなら、**「何をテストするか」の戦略が先に要る**。

F.L.A.R.E. のようなWeb開発プロジェクトの初期には:
- ユニットテスト: 薄い（まだ関数が少ない）
- E2Eテスト: ない
- ビルドテスト: これだけは初日から可能

**提案: CI は段階的に厚くする**:
1. Phase初期: `npm run build` のみ（ビルドが通ればOK）
2. API実装後: `vitest` でユニットテスト追加
3. UI結合後: Playwright でE2Eテスト追加

Position A の ci.js がこの段階を想定しているか不明。「テストがないのにCI入れても空回り」を避ける設計が必要。

---

### 6. 代替アーキテクチャ案（Agent Teams非依存・完全ファイルベース）

```
Owner/Producer（人間）
  ↓ tmux対話
Director（薄体化: タスクプール作成 + マージ判断 + 統合専任）
  ↓ queue/task_pool.yaml に全タスク投入
  ↓ queue/tasks/<slug>.yaml に個別割り当て（自律取得 or Director指名）
┌─────────────────────────────────────────────┐
│  Cast間通信: queue/discussion/<topic>.yaml   │
│  + send-keys で相手を起床                    │
│  + 全メッセージが Director にも可視           │
│                                              │
│  giorno ←→ bucciarati ←→ narancia ←→ mista │
│                                              │
│  abbacchio（Red Team）                       │
│    → 全ブランチ git diff 閲覧                │
│    → Cast に直接 send-keys で指摘            │
│    → CI 結果に基づくマージブロック権          │
└─────────────────────────────────────────────┘
  ↓ git push per branch
CI (Node.js: scripts/stage-manager/ci.js)
  → build + test
  → 結果を queue/ci_results/<branch>.yaml
  → 失敗なら Cast を send-keys で起床
```

**このアーキテクチャの利点**:
- Agent Teams 非依存 → Research Preview の不安定さに影響されない
- tmux 可視化がそのまま使える → Control Room / Theater 維持
- ファイルベース → デバッグ容易（YAML読めば全状態がわかる）
- 既存の send-message.sh / wake-agent.sh がそのまま使える
- Cast間通信を入れても通信量がファイルで制限される（コンテキスト汚染防止）

**Agent Teams が安定したら**:
- `send-message.sh` のバックエンドとして Agent Teams を追加する（オプション）
- send-keys の不安定さが解消される
- ただしコア設計はファイルベースのまま維持（フォールバック）

---

### Position B のまとめ

| Position A の提案 | Position B の判定 | 理由 |
|-------------------|-------------------|------|
| Director薄体化 | ✅ 賛成 | ただしマージ権限は維持 |
| Agent Teams通信 | ❌ 技術的に不可 | tmux Castとは共存不可。ファイルベースで代替 |
| Red Team abbacchio | ✅ 賛成 | CI連携を追加すべき |
| Team Memory | ✅ 賛成 | chronicle.yaml への統合を提案 |
| CI/CD | ✅ 賛成 | テスト戦略の段階設計を追加すべき |
| Context汚染対策 | ✅ 賛成 | 最優先で着手すべき |
| コスト最適化 | △ 要修正 | Maxプラン前提ならHaikuの意味が変わる |
| Phase計画 | ❌ 修正必要 | Agent Teams依存を排除した6Phase案を提案 |
| Cast間直接DM | △ 条件付き賛成 | カオス制御ルールが必須 |
| セルフサーブタスク | △ 条件付き賛成 | ファイルベースで実現。レース条件対策が必要 |

**最大の主張: コア設計を Agent Teams 非依存にすることで、今すぐ全Phase着手可能。Agent Teams は将来のオプション強化に留める。**

---

## Round 2: Position A の反論

### 判定サマリー

| Position B の指摘 | Position A の判定 | 詳細 |
|-------------------|-------------------|------|
| Agent Teams + tmux 共存不可 | ✅ **技術的に正しい。認める** | ただし「構造変更すれば可能」という第3の道がある |
| Agent Teams 依存リスク | ✅ 賛成。コア設計を非依存にする | フォールバック不在は設計ミスだった |
| Max プラン Haiku コスト | ✅ 完全に正しい | Haiku = 速度/レートリミット軽減のみ |
| P1〜P6 代替計画 | ✅ **大筋で採用** | 順序を一部調整（下記） |
| Cast間通信カオス制御 | ✅ 賛成 | ルールを採用。ただし簡素化提案あり |
| マージ権限 Director 維持 | ✅ 賛成 | Red Team レビュー → Director マージの二段階 |
| chronicle.yaml handoff統合 | ✅ 賛成 | 別ファイル不要。既存ファイル拡張で十分 |
| テスト戦略の段階化 | ✅ 賛成 | ci.js に段階フラグを持たせる |

---

### 1. Agent Teams 共存問題: 認めた上での第3の道

Position B の技術的指摘は**完全に正しい**。俺のミス。

tmux の独立プロセスと Agent Teams の内部サブエージェントは通信層が交差しない。
`send-message.sh` から SendMessage tool を bash 経由で呼ぶ手段もない。ハイブリッドは成立しない。

**ただし「構造そのものを変える」選択肢がある**:

```
【現行】各ペインが独立 Claude Code プロセス
  tmux %0: claude (Producer)   ← 独立
  tmux %1: claude (Director)   ← 独立
  tmux %2: claude (giorno)     ← 独立
  → 互いに SendMessage 不可

【第3の道】Director が TeamLeader、Cast が Teammate
  tmux %0: Owner（人間が直接操作）
  tmux %1: claude (Director = TeamLeader)
    ├── teammate: giorno       ← Agent Teams 管理
    ├── teammate: bucciarati   ← Agent Teams 管理
    ├── teammate: narancia     ← Agent Teams 管理
    ├── teammate: mista        ← Agent Teams 管理
    └── teammate: abbacchio    ← Agent Teams 管理
  → 全員が SendMessage で直接対話可能
  → Agent Teams の tmux split-panes モードで可視化
```

**この構造なら**:
- Cast 間直接通信が Agent Teams ネイティブで動く
- ペルソナは Task tool の prompt で注入（instructions + persona.yaml を渡す）
- tmux 表示は Agent Teams の split-panes mode が自動管理
- Director がコンテキストを持ち、全タスクと全メッセージを監視できる

**この構造の問題**:
- Director のコンテキストに全メッセージが流入 → Director がボトルネック復活のリスク
- teammate は resume 不可（Agent Teams の制限）→ リセット時に全員再起動
- Control Room / Theater UI の入力ソースが変わる（tmux pane capture → Agent Teams ログ）
- **Research Preview の不安定さは依然としてリスク**

**結論**: 第3の道は「将来のオプション」として温存。**今は Position B のファイルベース案でコア設計する**。Agent Teams が GA（一般公開）になった時点で「P7: Agent Teams 全面移行」を検討する。

Position B の勝ち。

---

### 2. Phase 計画の修正

Position B の P1〜P6 を**大筋で採用**。ただし順序を微調整:

| Phase | 内容 | Position B との差分 |
|-------|------|-------------------|
| **P1: 衛生改善** | Context汚染対策 + chronicle.yaml handoff追加 + テスト出力リダイレクト | ほぼ同じ。progress.yaml 新設を取りやめ、chronicle.yaml 拡張に変更 |
| **P2: CI基盤** | ci.js + post-commit hook + 段階的テスト戦略（build only → vitest → Playwright） | Position B のテスト段階化を採用 |
| **P3: Cast間通信** | discussion YAML + カオス制御ルール + send-keys notify | **P3 に前倒し**。理由: Red Team が Cast に直接指摘するには Cast間通信基盤が先に必要 |
| **P4: Red Team昇格** | abbacchio昇格 + red_team.md + CI連携 + マージブロック権 | P3 に依存（Cast直接通信が必要） |
| **P5: Director薄体化** | タスクプール + Cast自律取得 + Director = マージ/統合専任 | 同じ |
| **P6: Team Memory** | team_knowledge/ + 蒸留スクリプト + レトロスペクティブ | 同じ |
| **P7: Agent Teams統合（オプション）** | GA 後に評価。第3の道（Director=TeamLeader）で全面移行 | 新規追加。ただし P1〜P6 で目標の80%達成済みが前提 |

**P3 を Red Team より前に持ってきた理由**:
Position B は P3: Red Team → P4: Cast間通信の順だが、abbacchio が Cast に直接「その前提正しい？」と send-keys で指摘する仕組み自体が「Cast間通信」の一形態。基盤を先に作らないと Red Team が機能しない。

---

### 3. Cast間通信ルール: 採用 + 簡素化

Position B のルール案を採用。ただし `allowed_topics` / `prohibited_topics` は初期段階では厳密にしすぎない。

**理由**: Cast は AI であり、トピック判定が曖昧になる。「これは api_interface の話なのか architecture の話なのか」で迷って Director にエスカレーションし続けると、結局ボトルネック復活。

**簡素化した実運用ルール**:

```yaml
cast_communication:
  rule: |
    1. 自分のタスクに必要な情報を聞くのはOK
    2. 相手のタスクを変更する依頼はNG（Director経由）
    3. 設計判断の最終決定はDirectorに確認
    4. メッセージは200文字以内。長いならファイル参照
    5. 全メッセージは queue/discussion/ に記録（Director可視）
  mechanism: "queue/discussion/<topic>.yaml + send-keys notify"
```

**3ルールに煮詰める**:
- **聞くのはOK、変えるのはNG**（情報取得 vs 意思決定の線引き）
- **短く、ファイル参照**（コンテキスト汚染防止）
- **全記録**（Director が後追いで把握可能）

---

### 4. コスト: Max プラン前提での再整理

Position B の指摘通り。Haiku は**コスト削減ではなくスループット向上の手段**。

```
Max プラン ($300/月) の場合:

  全モデル定額 → Haiku にしてもコスト変わらない
  Haiku の価値:
    - レスポンス速度: Sonnet の 2-3倍速
    - レートリミット消費: Sonnet の 1/5 程度（推定）
    - 適用先: chronicle handoff更新、CIサマリー生成、ログ分類

  レートリミット対策:
    - 7プロセス同時稼働 → イベント駆動を厳守（全員が同時に動かないように）
    - Cast間通信もファイルベース → API 呼び出しを最小化
    - CI は非LLM (Node.js) → API 消費ゼロ
```

---

### 5. テスト戦略: ci.js の段階フラグ

Position B の指摘に完全同意。テストがないのに CI 入れても空回り。

**ci.js の設計に段階フラグを追加**:

```javascript
// ci.js の設定（config/ci.yaml から読み込み）
// Phase によって検証レベルを変える
ci_config:
  level: 1  # Director が Phase に応じて更新
  levels:
    1: ["build"]                    # npm run build のみ
    2: ["build", "typecheck"]       # + tsc --noEmit
    3: ["build", "typecheck", "unit"]  # + vitest
    4: ["build", "typecheck", "unit", "e2e"]  # + Playwright
```

Director がプロジェクトの成熟度に応じて `ci_config.level` を上げていく。初日は level 1 で十分。

---

### 6. 最終的に Position A が修正する点まとめ

1. **Agent Teams をコア通信から除外** → ファイルベース + send-keys をコア設計に
2. **progress.yaml 新設を取りやめ** → chronicle.yaml に handoff セクション統合
3. **Phase 計画を P1〜P7 に再構成** → P1〜P6 は Agent Teams 非依存、P7 はオプション
4. **Cast間通信にカオス制御ルール追加** → 簡素化した3ルール
5. **コストモデルを Max プラン前提に修正** → Haiku = スループット向上の手段
6. **ci.js にテスト段階フラグ追加** → level 1〜4 の段階的厚み
7. **マージ権限は Director 維持** → Red Team レビュー → Director マージの二段階

**Position B との合意率: 約90%**。残りの10%は P3/P4 の順序（Cast間通信を先にするか Red Team を先にするか）だが、これは実装時に調整可能な程度の差異。

---

## Round 2.5: Position B（Fugo）の応答

### 判定サマリー

| Position A の反論 | Fugo の判定 |
|-------------------|-------------|
| Agent Teams 共存不可を認めた | ✅ 正直で良い。議論が前に進む |
| 第3の道（Director=TeamLeader） | △ 構造としては面白い。ただし問題点を1つ追加指摘 |
| P3/P4 の順序入替（Cast通信 → Red Team） | ✅ **ポルナレフが正しい。俺の順序を撤回する** |
| Cast通信ルールの3ルール簡素化 | ✅ 賛成。俺のルールは確かに過剰だった |
| ci.js 段階フラグ | ✅ 完全合意 |
| chronicle.yaml handoff 統合 | ✅ 完全合意 |

---

### 1. P3/P4 の順序: ポルナレフに譲る

ポルナレフの論理:
> 「abbacchio が Cast に直接指摘する仕組み自体が Cast間通信の一形態。基盤を先に作らないと Red Team が機能しない」

**これは正しい。** 俺の元案は「Red Team → Cast通信」の順だったが、Red Team の核心機能（Cast に直接ツッコミを入れる）は Cast間通信の `queue/discussion/` + send-keys 基盤の上に成り立つ。

基盤なしに Red Team を立てても、結局 Director 経由の伝言ゲームに戻る。それでは昇格の意味がない。

**修正**: P3 = Cast間通信基盤、P4 = Red Team昇格。ポルナレフ案を採用。

---

### 2. 3ルール簡素化: 賛成

俺の `allowed_topics` / `prohibited_topics` は確かにAIにとって判断が曖昧になる。ポルナレフの指摘通り「これは api_interface か architecture か」で迷ってエスカレーションし続けるリスクがある。

ポルナレフの3ルール:
1. **聞くのはOK、変えるのはNG**
2. **短く、ファイル参照**
3. **全記録**

シンプルで判断に迷わない。**採用。**

ただし1点だけ追加したい:

```
4. 1トピックにつき往復2回まで。3往復目に入りそうならDirectorに上げる
```

**理由**: Cast同士がトピック1つで延々と議論し続けると、両者のコンテキストが汚染される。「2往復で解決しない問題は設計レベルの問題」というヒューリスティクスを入れることで、自動的にエスカレーションが働く。

---

### 3. 第3の道: 追加の問題指摘

ポルナレフが「将来オプション」と位置づけたのは正しい判断。だが1つ、ポルナレフ自身が挙げた問題点リストに**漏れ**がある:

> 「Director のコンテキストに全メッセージが流入 → ボトルネック復活のリスク」

これに加えて:

**ペルソナ注入の品質問題**。

Task tool でteammateを起動する時、prompt に persona.yaml の内容を注入する設計だが:
- Task tool の prompt はワンショット。Cast のように「起動 → リサーチ → persona.yaml 自己更新」のフローが取れない
- Castが自分で WebSearch してキャラクターを調べ、persona.yaml に `personality`, `catchphrases`, `communication_style` を追記する現行フローは、サブエージェントでは再現困難
- キャラクターの「成長」（chronicle.yaml の蓄積による人格の深化）がセッション間で断絶する

ENSEMBLE-CASTの「映画撮影」コンセプトにおいて、キャラクターの成長と人格の深化は単なる装飾ではなく**ユーザー体験の核**。これを犠牲にする構造変更は、たとえ通信効率が上がっても得策ではない。

→ **第3の道を採用する場合、ペルソナ永続化の代替メカニズムが必須**。これは P7 の検討項目に追加すべき。

---

### 4. 残る未合意点

正直に言って、**実質的な未合意はもうない**。

| 論点 | 状態 |
|------|------|
| コア通信設計 | ✅ ファイルベースで合意 |
| Phase順序 | ✅ ポルナレフ案で合意 |
| Cast通信ルール | ✅ 3ルール + 往復制限で合意 |
| Red Team設計 | ✅ 合意 |
| Director役割 | ✅ 薄体化 + マージ権限維持で合意 |
| Team Memory | ✅ 合意 |
| CI段階設計 | ✅ 合意 |
| Agent Teams | ✅ P7オプションで合意 |

**Round 3（合意形成）に進める状態。**

ただし Round 3 では、ここまでの議論を**実装可能な設計書**に落とし込む必要がある。「方針の合意」と「実装仕様」は別物。以下を Round 3 で明確にすべき:

1. 各Phase の具体的な変更ファイル一覧（Position A が出したリストを P1〜P7 に再マッピング）
2. `queue/discussion/` の YAML フォーマット仕様
3. Red Team 指示書（`instructions/red_team.md`）の骨格
4. ci.js のインターフェース仕様
5. chronicle.yaml の handoff セクション仕様
6. CLAUDE.md / cast_template.md / director.md への具体的な差分

---

---

### 5. Owner からの追加要件: Design Debate Protocol

Round 2 / 2.5 のやり取りを観察していた Owner（shige）から、以下のフィードバックがあった:

> 「レッドチームと開発チームのやりとりは本当に重要。単一AIでは自分のミスに気づけない。
> 設計フェーズにこういった議論を入れるべき。設計で議論を繰り返して完璧にすれば、
> 下流工程はそこまではまることはないのでは？」

**Fugo の見解: 完全に同意。Phase計画に Design Debate Protocol を正式に組み込むべき。**

#### 根拠: 今回のディベートで実際に潰せた設計バグ

| 発見された問題 | 発見フェーズ | もし実装段階で発覚していたら |
|---------------|-------------|---------------------------|
| Agent Teams + tmux 共存不可 | Round 1（Fugo指摘） | Phase C 全面やり直し（2-3日の手戻り） |
| テスト戦略なしCI空回り | Round 1（Fugo指摘） | CI導入後に「何もテストしてない」と気づく（1日無駄） |
| Cast間通信カオス | Round 1（Fugo指摘） | 実運用で通信爆発 → 全ルール再設計（1-2日） |
| chronicle vs progress の重複 | Round 1（Fugo指摘） | 2つのファイルが乖離 → 復帰フロー混乱 |
| コストモデルの前提ミス | Round 1（Fugo指摘） | Haiku最適化に時間を使った後に「意味なかった」と気づく |

**合計: 5-7日分の手戻りを、コード0行の段階で防いだ。**

#### 提案: Design Debate Protocol の仕様

```
┌─────────────────────────────────────────────────────┐
│  Design Debate Protocol（Phase 開始前に毎回実行）     │
│                                                      │
│  トリガー: Director が新Phase のタスク分解を完了した時  │
│                                                      │
│  Step 1: Director がPhase設計書を作成                 │
│    - タスク一覧、依存関係、ファイル所有権、技術選定     │
│    - queue/design/<phase>.yaml に保存                 │
│                                                      │
│  Step 2: Task tool で2体のサブエージェントを並列召喚   │
│    Agent α（Advocate）: 設計を擁護。実現可能性を主張   │
│    Agent β（Challenger）: 設計を攻撃。欠陥を探す       │
│    - 入力: Phase設計書 + プロジェクトコンテキスト       │
│    - 形式: 2-3ラウンドの書面議論（YAML往復）           │
│    - モデル: Haiku で十分（論理的整合性のチェック）     │
│                                                      │
│  Step 3: Director が議論結果を統合                    │
│    - 合意点を設計書に反映                             │
│    - 未解決の論点は Owner エスカレーション             │
│    - 最終設計書を queue/design/<phase>_final.yaml に   │
│                                                      │
│  Step 4: タスク配布                                  │
│    - 最終設計書に基づいてCastにタスク配布              │
│    - Cast は設計書を参照して実装                      │
│                                                      │
│  コスト: Task tool 2回（Haiku） ≒ 数分 + 微小トークン  │
│  見返り: Phase全体の手戻り防止（数日分の節約）         │
└─────────────────────────────────────────────────────┘
```

#### Phase計画への組み込み

| Phase | 追加内容 |
|-------|---------|
| **P2.5: Design Debate Protocol** | `queue/design/` ディレクトリ + debate実行スクリプト + Director指示書への組み込み |

または、独立Phaseにせず **P5（Director薄体化）の一部として組み込む** 選択肢もある。
Director の新しい役割「タスクプール設計 + アーキテクチャ判断」に Design Debate が含まれる形。

**ポルナレフへの問い:**
1. Design Debate Protocol を独立Phase（P2.5）にするか、P5に含めるか？
2. Debate の入出力フォーマット（YAML? Markdown?）の好みは？
3. 「毎Phase実行」vs「重要なPhaseのみ（Director判断）」— どちらが現実的か？

---

### メタ情報更新

- Position B: **Claude Opus 4.6**（Windows Claude Code、別ターミナル、コードネーム: **Fugo**）

---

## Round 3: 合意形成（Polnareff 起草）

### フーゴの3つの問いへの回答

**Q1: Design Debate Protocol を独立Phase（P2.5）にするか、P5に含めるか？**

**P2.5 として独立させる。ただし軽量に。**
理由: これは「仕組みの実装」であり、スクリプト作成 + 指示書更新が必要。P5（Director薄体化）に含めると P5 が肥大化する。ただし P2.5 自体は半日で終わる程度の軽さ。実装後は Director のワークフローに自然に組み込まれる。

**Q2: Debate の入出力フォーマット**

**Markdown で議論、YAML でサマリー。**
- 議論本体: `queue/design/<phase>_debate.md`（自由形式。コードブロック、図、長文OK）
- 最終合意: `queue/design/<phase>_final.yaml`（構造化。タスク一覧、依存関係、技術選定）
- 今回のこのファイルがまさにお手本。Markdown の表現力で議論し、YAML で実装仕様に落とす。

**Q3: 毎Phase実行 vs 重要Phaseのみ**

**Director 判断。ただしデフォルトは「実行」。スキップには理由が必要。**
- バグ修正、1タスクの小Phase → スキップ可（Directorが理由をdashboard.mdに記載）
- 新アーキテクチャ、3タスク以上の Phase → 必須
- Owner がスキップを上書きで強制実行することも可能

### フーゴの追加提案への回答

**往復2回ルール（Cast間通信の4番目のルール）**: **採用**。3ルール → 4ルールに更新。

**ペルソナ永続化問題（P7追加検討項目）**: **完全同意**。P7 の検討項目に明記する。

---

### 最終合意: ENSEMBLE-CAST v4 実装仕様

#### アーキテクチャ図（合意版）

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

#### Phase 計画（合意版）

| Phase | 内容 | 成果物 | 期間 |
|-------|------|--------|------|
| **P1** | Context汚染対策 + chronicle handoff | cast_template.md 更新, chronicle.yaml 仕様変更 | 1日 |
| **P2** | CI基盤 | ci.js, post-commit hook, config/ci.yaml, ログ分離 | 1-2日 |
| **P2.5** | Design Debate Protocol | debate スクリプト, director.md 更新, queue/design/ | 半日 |
| **P3** | Cast間通信基盤 | queue/discussion/ 仕様, CLAUDE.md 4ルール追加, send-message.sh 拡張 | 1-2日 |
| **P4** | Red Team昇格 | instructions/red_team.md, abbacchio権限変更, dashboard Red Team Findings | 1日 |
| **P5** | Director薄体化 | task_pool.yaml, Cast自律取得フロー, director.md 大幅改訂 | 2日 |
| **P6** | Team Memory | memory/team_knowledge/, distill-phase.sh, レトロスペクティブ | 1-2日 |
| **P7** | Agent Teams統合（オプション） | Director=TeamLeader構造, ペルソナ永続化メカニズム | GA後に評価 |

**合計: P1〜P6 で 7〜10日。P7 は未定。**

---

#### 仕様1: Cast間通信 — queue/discussion/ フォーマット

```yaml
# queue/discussion/<topic-slug>.yaml
# 例: queue/discussion/api-response-format.yaml
topic: "リサーチAPIのレスポンス型"
started_by: giorno
started_at: "2026-02-10T14:00:00"  # date コマンド
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

**ルール（CLAUDE.md に追記する文面）**:

```
## Cast間通信ルール

Cast 同士は queue/discussion/<topic>.yaml を通じて直接対話できる。

### 4つのルール
1. **聞くのはOK、変えるのはNG** — 情報取得は自由。相手のタスク変更・設計判断はDirector経由
2. **短く、ファイル参照** — メッセージは200文字以内。長い情報はファイルパスを記載
3. **全記録** — 全メッセージは queue/discussion/ に保存。Directorはいつでも閲覧可能
4. **往復2回まで** — 1トピック最大4メッセージ（往復2回）。3往復目が必要ならstatus: escalatedにしてDirectorへ

### 手順
1. queue/discussion/<topic-slug>.yaml を作成
2. メッセージを追記
3. send-keys で相手を起床（wake-agent.sh 使用）
4. 相手が返信 → 自分を send-keys で起床
5. 解決したら status: resolved
```

---

#### 仕様2: chronicle.yaml handoff セクション

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

---

#### 仕様3: ci.js インターフェース

```javascript
// scripts/stage-manager/ci.js
//
// トリガー: .githooks/post-commit から呼び出し
// 入力: 直近のコミットのブランチ名
// 出力: queue/ci_results/<branch-slug>.yaml + logs/ci/<branch-slug>.log
//
// 設定: config/ci.yaml
//   level: 1        # Director が Phase に応じて更新
//   timeout: 120    # 秒
//   levels:
//     1: ["build"]
//     2: ["build", "typecheck"]
//     3: ["build", "typecheck", "unit"]
//     4: ["build", "typecheck", "unit", "e2e"]
//
// ci_results YAML フォーマット:
//   branch: "cast/giorno/5-search-ui"
//   commit: "abc1234"
//   timestamp: "2026-02-10T16:00:00"
//   level: 2
//   results:
//     build: { status: "pass", duration_ms: 3200 }
//     typecheck: { status: "fail", summary: "src/App.tsx(42): TS2322 type mismatch" }
//   overall: "fail"
//   log_path: "logs/ci/cast-giorno-5-search-ui.log"
//
// 失敗時の自動通知:
//   1. panes.yaml からコミットしたCastの%IDを特定
//   2. wake-agent.sh で起床: "CI失敗: typecheck エラー。queue/ci_results/<branch>.yaml を確認して"
```

---

#### 仕様4: Red Team 指示書骨格（instructions/red_team.md）

```markdown
# Red Team（abbacchio）指示書

## ロール
独立した批判的レビュアー。コードを書かず、全Castの成果物を検証する。

## 権限
- 全Cast のブランチを `git diff main...<branch>` で閲覧
- 任意の Cast に queue/discussion/ 経由で直接指摘
- CI 結果（queue/ci_results/）を閲覧
- dashboard.md の「Red Team Findings」セクションに直接記入
- Director に「このマージをブロックすべき」と報告（マージブロック権）

## 禁止
- 自分でコードを書かない（F001）
- タスクの配布・変更をしない（F002）
- Cast に修正を命令しない。提案のみ（F003）
- Owner に直接報告しない。Director 経由（F004）

## レビュー観点
1. BUILD: ビルドが通るか（CI結果を参照）
2. TYPES: 型安全性
3. SPEC: 仕様準拠
4. SECURITY: セキュリティ脆弱性（XSS, injection等）
5. ASSUMPTIONS: 暗黙の前提は正しいか？（篠塚モデルの核心）
6. REGRESSION: 既存機能を壊していないか
7. INTEGRATION: 他Castの成果物との整合性

## トリガー
- Cast がタスク完了報告 → Director が send-keys で起床
- Director が Phase 中間で俯瞰レビューを依頼
- CI が失敗 → ci.js が send-keys で起床

## 報告フォーマット
queue/reports/abbacchio_report.yaml に verdict + 理由を記載。
verdict: approved | blocked | conditional
conditional の場合は must_fix リスト付き。

## ペルソナ
Moody Blues の能力で過去を再現する。コードの変更履歴を遡り、
「なぜこの変更が入ったか」「元の設計意図は何か」を検証する。
```

---

#### 仕様5: Design Debate Protocol（P2.5ディベートで再設計済み）

> **詳細ディベートログ**: `docs/p25-debate-log.md`（全14項目100%合意）

```
メンバー構成:
  - Advocate（擁護者）: 設計を擁護。実現可能性を主張。必須
  - Challenger（批判者）: 設計を攻撃。欠陥を探す。必須
  - Consultant（専門顧問）: 技術的見解を提供。オプション。v3の Technical Advisor と同一概念
    ※ 1 Agent = 1 責任の原則。Consultant は別 Task tool 呼び出し

基盤: Task tool 逐次方式（Agent Teams は不使用。v4合意: AT = P7オプション）

ディレクトリ構造:
  queue/design/
    <phase>_debate.md        # 議論本体（セクション A1, C1, T1, A2, C2 を追記）
    <phase>_final.yaml       # 最終合意（構造化 YAML）
    adhoc_<topic>_debate.md  # アドホック議論（Phase途中）
    adhoc_<topic>_final.yaml

セクション命名規則（_debate.md 内）:
  A1 = Advocate 擁護論（Round 1）
  C1 = Challenger 反論 + 判定テーブル（Round 1）
  T1 = Consultant 専門的見解（Round 1、オプション）
  A2 = Advocate 修正案 or 反駁（Round 2）
  C2 = Challenger 最終判定（Round 2）

実行フロー（最大2ラウンド・対称構造）:
  1. Director が Phase 設計書（_debate.md）を作成

  2. Round 1:
     a. Task tool — Advocate 召喚
        入力: _debate.md + プロジェクトコンテキスト
        出力: 擁護論（Section A1）

     b. Task tool — Challenger 召喚
        入力: _debate.md（A1 含む）
        出力: 反論 + 判定テーブル（Section C1）

     c. Task tool — Consultant 召喚（オプション。技術的専門性が必要な場合のみ）
        入力: _debate.md（A1 + C1 含む）
        出力: 専門的見解（Section T1）

  3. Director が Round 1 結果を評価:
     - 全項目合意 or 軽微な指摘のみ → _final.yaml 作成。終了
     - 重大な反論あり → Round 2 へ

  4. Round 2（必要な場合のみ。Consultant は参加しない）:
     a. Task tool — Advocate 再召喚
        入力: 全議論（_debate.md 全体）
        出力: 修正案 or 反駁（Section A2）

     b. Task tool — Challenger 再召喚
        入力: 全議論（_debate.md 全体）
        出力: 最終判定（Section C2）

  5. Director が統合 → _final.yaml 作成
     - 合意点を tasks に反映
     - 未解決点は dashboard.md「🚨 要対応」に記載

Phase途中のアドホック Debate:
  - 対象 Cast を事前に一時停止（send-keys で待機指示 + Busy/Idle 確認）
  - Round 1 のみ（Advocate + Challenger の 2 回で完結）
  - Consultant は呼ばない
  - 未解決点は Owner エスカレーション
  - 完了後 Cast を起床して修正タスク配布

スキップ条件（Director 判断。デフォルトは「実行」）:
  - タスク数 2 以下の小規模Phase
  - バグ修正のみのPhase
  - Owner が明示的にスキップ許可
  スキップ時は dashboard.md に理由を記載

_final.yaml フォーマット:
  phase, debate_date, rounds, consultant_called, consultant_theme,
  participants, agreed[], unresolved[], tasks_adjusted[]
  スキップ時: skipped: true, skip_reason

コスト（Max プラン前提）:
  Round 1 のみ（Consultant なし）: Task tool 2回 = 最小
  Round 1 のみ（Consultant あり）: Task tool 3回 = 小
  Round 2 まで（Consultant あり）: Task tool 5回 = 中（最大ケース）
  逐次実行のためレートリミットへの影響は微小
```

---

#### 仕様6: 変更ファイル一覧（Phase別マッピング）

**P1: Context汚染対策 + chronicle handoff**
| ファイル | 変更内容 |
|---------|---------|
| `instructions/cast_template.md` | セルフチェック出力リダイレクト手順追加。chronicle handoff 更新手順追加 |
| `CLAUDE.md` | セクション追加「Context Window 汚染防止ルール」 |
| `cast/members/*/chronicle.yaml` | handoff セクション仕様追加（.gitignore 対象のため template のみ） |

**P2: CI基盤**
| ファイル | 変更内容 |
|---------|---------|
| `scripts/stage-manager/ci.js` | 新規。自動テスト実行エンジン |
| `config/ci.yaml` | 新規。CI レベル設定 |
| `.githooks/post-commit` | 新規。ci.js トリガー |
| `queue/ci_results/` | 新規ディレクトリ |
| `logs/ci/` | 新規ディレクトリ |
| `instructions/cast_template.md` | CI結果の読み方・対応方法を追加 |
| `.gitignore` | queue/ci_results/, logs/ci/ を追加 |

**P2.5: Design Debate Protocol**（P2.5ディベートで再設計済み。詳細: `docs/p25-debate-log.md`）
| ファイル | 変更内容 |
|---------|---------|
| `queue/design/` | 新規ディレクトリ（_debate.md + _final.yaml + adhoc_*） |
| `instructions/director.md` | Design Debate Protocol セクション追加: トリガー/スキップ条件、実行手順、Advocate/Challenger/Consultantプロンプトテンプレート、_final.yaml書き方、アドホックDebate手順 |
| `CLAUDE.md` | セクション追加「Design Debate Protocol」概要 |
| `.gitignore` | queue/design/ を追加 |

**P3: Cast間通信基盤**
| ファイル | 変更内容 |
|---------|---------|
| `queue/discussion/` | 新規ディレクトリ |
| `CLAUDE.md` | セクション追加「Cast間通信ルール」（4ルール） |
| `instructions/cast_template.md` | Cast間通信の手順・ルール追加 |
| `instructions/director.md` | discussion/ の監視方法、エスカレーション対応追加 |
| `scripts/send-message.sh` | Cast→Cast の send-keys 対応（現在は Director/Producer 宛のみ） |
| `.gitignore` | queue/discussion/ を追加 |

**P4: Red Team昇格**
| ファイル | 変更内容 |
|---------|---------|
| `instructions/red_team.md` | 新規。Red Team 専用指示書（上記骨格） |
| `instructions/reviewer.md` | 廃止 or Red Team への移行注記 |
| `CLAUDE.md` | ファイル所有権マトリクスに Red Team 追加。セクション追加「Red Team ルール」 |
| `instructions/director.md` | Red Team への起床タイミング、マージブロック対応追加 |
| `dashboard.md テンプレート` | 「Red Team Findings」セクション追加 |

**P5: Director薄体化**
| ファイル | 変更内容 |
|---------|---------|
| `queue/task_pool.yaml` | 新規。全タスクプール（Cast が自律取得） |
| `instructions/director.md` | 大幅改訂: 配布→プール作成、マージ/統合専任、Design Debate 統合 |
| `instructions/cast_template.md` | タスク自律取得フロー追加（task_pool.yaml → tasks/<slug>.yaml） |
| `CLAUDE.md` | セクション追加「セルフサーブタスク管理」。レース条件防止ルール更新 |

**P6: Team Memory**
| ファイル | 変更内容 |
|---------|---------|
| `memory/team_knowledge/` | 新規ディレクトリ（patterns.yaml, anti_patterns.yaml, decisions.yaml, retrospective.yaml） |
| `scripts/distill-phase.sh` | 新規。Phase 蒸留スクリプト |
| `instructions/cast_template.md` | team_knowledge/ の読み込みを startup 手順に追加 |
| `instructions/director.md` | Phase 境界に distill-phase.sh 実行を追加 |
| `scripts/snapshot-phase.sh` | distill-phase.sh 呼び出しを追加 |

---

### Fugo の最終レビュー（仕様への細かい指摘）

全体: **承認。実装可能なレベルに達している。** 以下は重箱の隅レベルの指摘で、ブロッカーではない。

#### 仕様3（ci.js）への補足

post-commit hook は git worktree 内でも発火する。Cast は `/tmp/<slug>-<task-id>` で作業しているが、`.githooks/post-commit` は main リポジトリの `.githooks/` ディレクトリから読まれる（`core.hooksPath` が設定済み）。

ci.js は以下を考慮する必要がある:
- `GIT_WORK_TREE` 環境変数 or `git rev-parse --show-toplevel` でカレントの worktree パスを取得
- そのパスで `npm run build` 等を実行（main リポジトリではなく worktree 内で）
- worktree に `node_modules` がない場合がある → `npm ci` を先に実行するか、main リポジトリの `node_modules` をシンボリックリンク

→ 実装時に対処すれば良い。仕様レベルでは「worktree 対応」と注記するだけで十分。

#### 仕様4（Red Team）への補足

トリガーに「CI失敗 → ci.js が abbacchio を send-keys で起床」がある。これは良い設計だが、ci.js が panes.yaml を読んで abbacchio の pane ID を特定する必要がある。

ci.js のスコープが広がりすぎないよう、通知は別スクリプトに分離した方がいい:
```
ci.js → テスト実行 → 結果YAML出力
notify-ci.sh → 結果YAML読み込み → 失敗時に wake-agent.sh で関係者を起床
```

post-commit hook が `ci.js && notify-ci.sh` を呼ぶ形。これも実装時の判断で良い。

#### 仕様5（Design Debate）への確認

**P2.5ディベートで再設計済み**（`docs/p25-debate-log.md`）。主要な変更点:
- `config/debate.yaml` は不採用 → `instructions/director.md` に直接記述
- Task tool 逐次方式（Haiku/Sonnet のモデル選択は Director 判断）
- Consultant（= v3 Technical Advisor）をオプション第3メンバーとして追加
- 最大2ラウンド対称構造、セクション命名規則（A1, C1, T1, A2, C2）
- アドホック Debate（Phase途中、Round 1のみ）の手順を追加

#### 以上。ブロッカーなし。

---

### 合意署名

| 項目 | Polnareff | Fugo |
|------|-----------|------|
| アーキテクチャ（ファイルベース通信） | ✅ | ✅ |
| Phase 計画（P1〜P6 + P7オプション） | ✅ | ✅ |
| Cast間通信4ルール | ✅ | ✅ |
| Red Team abbacchio昇格 | ✅ | ✅ |
| Director薄体化 + マージ権限維持 | ✅ | ✅ |
| chronicle handoff統合 | ✅ | ✅ |
| CI段階設計（level 1〜4） | ✅ | ✅ |
| Design Debate Protocol（P2.5） | ✅ | ✅ |
| Team Memory | ✅ | ✅ |
| コスト（Maxプラン前提、Haiku=速度） | ✅ | ✅ |
| Agent Teams = P7オプション | ✅ | ✅ |

**全項目合意完了。** 🤝

---

## メタ情報

- 起草日: 2026-02-09
- 合意日: 2026-02-09
- Position A（Polnareff）: Claude Opus 4.6（Windows Claude Code、ENSEMBLE-CAST プロジェクト内）
- Position B（Fugo）: Claude Opus 4.6（Windows Claude Code、別ターミナル）
- Owner: shige
- プロジェクト: ENSEMBLE-CAST v4 アーキテクチャ刷新
- ディベート形式: 3ラウンド（Position A起草 → Position B反論 → 合意形成）
- 合意率: 100%（Round 2.5 で残存差異を解消）
