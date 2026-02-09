# P2.5 Design Debate Protocol — 再設計ディベート

> **議題**: ENSEMBLE-CAST v4 の P2.5 Design Debate Protocol を再設計する。
> Agent Teams（TeamCreate/SendMessage）による一時的な議論チームの活用と、
> 専門スタッフ（裏方）の召喚体系を設計する。
>
> **ディベート参加者**:
> - **Polnareff**（Advocate / 設計擁護者）: Claude Opus 4.6
> - **Fugo**（Challenger / 批判者）: Claude Opus 4.6

---

## Round 1: Polnareff の設計案

### 背景分析

現行 v4 設計（ensemble-v4-architecture.md）の P2.5 Design Debate は以下の設計:

```
Step 1: Director が Phase 設計書を作成
Step 2: Task tool で Advocate + Challenger を並列召喚（Haiku）
Step 3: 2-3 ラウンドの書面議論
Step 4: Director が統合 → 最終設計書
```

**問題点**:
1. Task tool はワンショット。サブエージェント間で「議論」が成立しない（各自が独立した報告を返すだけ）
2. Advocate と Challenger が互いの主張を見て反論する「ラウンド制」を Task tool で実現するには、Director が中継役になり、3ラウンドなら6回の Task tool 呼び出しが必要
3. 専門スタッフ（デザイナー、美術、工学等）の召喚が体系化されていない
4. Ownerの意図:「キャストより裏方の方が本来は多い。頭抱えて考えるチームが多い方が、より良い方向に進む」

### 提案: Agent Teams 一時議論チーム

#### 1. 仕組みの全体像

```
Director が設計レビューが必要と判断
  ↓
Director の tmux ペイン内で Agent Teams を起動
  ↓
TeamCreate で一時的な「企画会議チーム」を作成
  teammate: Advocate（擁護者）
  teammate: Challenger（批判者）
  teammate: 専門スタッフ（テーマに応じて0-2名追加）
  ↓
Director = Team Leader として議論を制御
  - 設計書を全員に broadcast
  - ラウンド進行を管理
  - 合意形成 or エスカレーション判断
  ↓
合意に達したら:
  - 最終設計書を queue/design/<phase>_final.yaml に保存
  - teammate 全員に shutdown_request
  - チーム解散
  ↓
Director は通常業務（Cast へのタスク配布）に復帰
```

#### 2. teammate の生存期間

**議論単位（1回の Design Debate で生成 → 解散）。**

理由:
- Phase 単位にすると、議論していない間もコンテキストを占有し続ける
- teammate の shutdown でコンテキストは消えるが、議論結果は `queue/design/` にファイルとして永続化される
- 次の Design Debate では新しい teammate を作る（前回の議論結果はファイルから読めばよい）

#### 3. Director のコンテキスト負荷対策

Agent Teams の teammate メッセージは Director（Team Leader）のコンテキストに流入する。対策:

1. **議論はファイルベースで行う**: teammate はメッセージで短い通知だけ送り、詳細な論点は `queue/design/<phase>_debate.md` に書き込む
2. **メッセージ長制限**: SendMessage の content は 200 文字以内。長い論点はファイル参照
3. **ラウンド制限**: 最大 3 ラウンド。3 ラウンドで合意しなければ未解決点を Owner にエスカレーション
4. **議論終了後に即 shutdown**: 議論が終わったら全 teammate を shutdown して、コンテキストへの追加流入を止める

#### 4. 専門スタッフの体系（映画メタファー）

映画制作の裏方にマッピングした専門家チーム:

| 映画用語 | 役割 | 召喚条件 | 得意分野 |
|---------|------|---------|---------|
| **Advocate**（脚本家A） | 設計を擁護・実現可能性を主張 | Design Debate 時（必須） | 設計の整合性、実装計画 |
| **Challenger**（脚本家B） | 設計を攻撃・欠陥を探す | Design Debate 時（必須） | リスク分析、前提の検証 |
| **Art Director**（美術監督） | UI/UX 設計レビュー | フロントエンド設計時 | レイアウト、コンポーネント設計、アクセシビリティ |
| **Cinematographer**（撮影監督） | アーキテクチャ/技術選定 | 新技術導入・スタック変更時 | パフォーマンス、スケーラビリティ、技術比較 |
| **Sound Designer**（音響設計） | API/データフロー設計 | バックエンド設計時 | API設計、データモデル、通信プロトコル |
| **Stunt Coordinator**（スタントコーディネーター） | セキュリティ/エッジケース | セキュリティ関連の変更時 | 脆弱性分析、エッジケース列挙、防御設計 |
| **VFX Supervisor**（VFX監督） | パフォーマンス/最適化 | パフォーマンス要件がある時 | バンドルサイズ、レンダリング最適化、キャッシュ戦略 |

**常設メンバー**: Advocate + Challenger（Design Debate 時に常に召喚）
**オンデマンド**: 残りの専門スタッフはテーマに応じて Director が判断

#### 5. 既存サブエージェント（v3）との関係

v3 で定義済みのサブエージェント:

| v3 サブエージェント | P2.5 専門スタッフ | 関係 |
|-------------------|-----------------|------|
| Script Supervisor | - | 別カテゴリ（レビュー時の召喚。Design Debate ではない） |
| Technical Advisor | Cinematographer | **統合**。Design Debate 時は Cinematographer として参加。レビュー時は Technical Advisor として召喚 |
| Location Scout | - | 別カテゴリ（調査専用。Design Debate 前に情報収集する役割） |
| Assistant Director | - | 別カテゴリ（Cast 管理補佐。Design Debate には参加しない） |
| Research Consultant | - | 別カテゴリ（リサーチ専用。Design Debate 前の情報収集） |

**つまり**: Design Debate の専門スタッフは「設計を議論するチーム」。v3 のサブエージェントは「実作業を補佐する個人」。カテゴリが異なる。
- **Design Debate スタッフ**: Agent Teams で一時チームを作り、複数人で議論
- **v3 サブエージェント**: Task tool でワンショット召喚、個別に報告して解散

#### 6. Advocate/Challenger との統合

Design Debate は専門スタッフの「上位カテゴリ」ではなく、**独立したプロトコル**。

```
Design Debate Protocol
  ├── 常設メンバー: Advocate + Challenger（対立構造）
  └── オプション参加: 専門スタッフ（テーマに応じて追加）
       └── Art Director, Cinematographer, Sound Designer, etc.
```

議論の進め方:
1. Advocate が設計を擁護する立場で主張
2. Challenger が設計を攻撃する立場で反論
3. 専門スタッフがいる場合、自分の専門分野から両者に意見を提出
4. Director が議論を統合し、合意点と未解決点を整理

**2体固定が基本。テーマに応じて専門家を 1-2 名追加。最大 4 名（Advocate + Challenger + 専門家 2 名）。**

#### 7. 実装上の制約への対応

| 制約 | 対応策 |
|------|--------|
| Agent Teams は Director の tmux ペイン内で完結 | OK。TeamCreate は Director のClaude Codeセッション内で動作。Cast の tmux ペインとは無関係 |
| Cast（giorno等）のペインとは干渉しない | OK。Agent Teams の teammate は tmux ペインを使わない。Director のセッション内サブプロセス |
| Max プラン($300/月)レートリミット | 議論中は Cast が作業中（API消費中）の場合がある → Design Debate は **Phase 開始前**に実行するので、Cast はまだ idle。レートリミット圧迫は限定的 |
| teammate の shutdown でコンテキスト消失 | 議論結果は `queue/design/` にファイル保存。shutdown 後もファイルは残る |

#### 8. 具体的な利用シーン

**シーン1: Phase 開始前の設計レビュー（従来の Design Debate）**

```
Director が Phase 3 のタスク分解を完了
  ↓
queue/design/phase3_debate.md に設計書を作成
  ↓
TeamCreate:
  - Advocate（model: sonnet）
  - Challenger（model: sonnet）
  - Sound Designer（バックエンド API 設計が含まれるため）
  ↓
3 ラウンドの議論 → 合意
  ↓
queue/design/phase3_final.yaml に最終設計書
  ↓
チーム解散 → Cast にタスク配布
```

**シーン2: Phase 途中で技術的に詰まった時**

```
Cast が status: blocked で報告。原因: アーキテクチャの根本的な判断が必要
  ↓
Director が問題を分析 → Design Debate が必要と判断
  ↓
TeamCreate:
  - Advocate（現設計を擁護）
  - Challenger（代替案を主張）
  - Cinematographer（技術的実現性の評価）
  ↓
2 ラウンドの議論 → 方針決定
  ↓
チーム解散 → 修正タスクを Cast に配布
```

**シーン3: Cast 間の設計方針が食い違った時の調停**

```
giorno と bucciarati の discussion が escalated（往復 2 回で未解決）
  ↓
Director が論点を整理 → Design Debate で第三者的に解決
  ↓
TeamCreate:
  - Advocate（giorno の立場を代弁）
  - Challenger（bucciarati の立場を代弁）
  ↓
2 ラウンドの議論 → Director が最終判断
  ↓
チーム解散 → 判断結果を両 Cast に通知
```

**シーン4: アーキテクチャ判断が必要な時**

```
新技術（例: Cloudflare D1 → Turso への移行検討）の導入判断
  ↓
Director が Location Scout を Task tool で事前召喚 → 技術調査レポート取得
  ↓
TeamCreate:
  - Advocate（移行を推進）
  - Challenger（現状維持を主張）
  - Cinematographer（技術比較の専門知識）
  ↓
3 ラウンドの議論 → 結論
  ↓
チーム解散 → 判断結果を Owner にエスカレーション or 自ら決定
```

#### 9. 具体的なプロンプト設計

**Advocate 起動プロンプト**:
```
あなたは Advocate（脚本家A）です。
Design Debate Protocol に基づき、提出された設計を擁護する立場で議論してください。

あなたの役割:
- 設計の実現可能性を主張する
- 設計の利点を具体的に説明する
- Challenger の指摘に対して論理的に反論する
- ただし、明らかに正しい指摘には素直に認める

議論のルール:
- 発言は queue/design/<phase>_debate.md にセクションを追記する形で行う
- SendMessage での通知は 200 文字以内（「Round 1 の主張をファイルに書いた。読んでくれ」程度）
- 最大 3 ラウンド
- ラウンドごとに「合意した点」「未合意の点」を明確にする

設計書: queue/design/<phase>_debate.md を読んでください。
```

**Challenger 起動プロンプト**:
```
あなたは Challenger（脚本家B）です。
Design Debate Protocol に基づき、提出された設計を批判的に検証する立場で議論してください。

あなたの役割:
- 設計の欠陥・リスクを発見する
- 暗黙の前提を疑う（「本当にそうか？」）
- 代替案を提示する
- ただし、建設的な批判に留める（破壊のための破壊はしない）

議論のルール:
（Advocate と同じ）

設計書: queue/design/<phase>_debate.md を読んでください。
```

**専門スタッフ起動プロンプト（例: Sound Designer）**:
```
あなたは Sound Designer（音響設計）です。
Design Debate に専門家として参加します。

あなたの専門分野:
- API 設計（RESTful, GraphQL, RPC）
- データモデル設計
- 通信プロトコルとデータフロー
- バックエンドアーキテクチャ

あなたの役割:
- Advocate と Challenger の議論を専門的知見から補完する
- 自分の専門分野で見落とされている問題を指摘する
- 技術的な実装コストの見積もりを提供する
- 対立する2者のどちらかに偏らない中立的立場

議論のルール:
（Advocate と同じ）

設計書: queue/design/<phase>_debate.md を読んでください。
```

#### 10. Director の議論制御フロー

```python
# 疑似コード: Director の Design Debate 実行フロー

def run_design_debate(phase, design_doc):
    # 1. 設計書を queue/design/ に保存
    write(f"queue/design/{phase}_debate.md", design_doc)

    # 2. テーマに応じて専門スタッフを決定
    specialists = determine_specialists(design_doc)
    # 例: フロントエンド設計 → [Art Director]
    # 例: バックエンド API → [Sound Designer]
    # 例: 技術移行 → [Cinematographer]
    # 例: シンプルな機能追加 → []（追加なし）

    # 3. Agent Teams でチーム作成
    team = TeamCreate(
        teammates = [
            { name: "advocate", prompt: ADVOCATE_PROMPT },
            { name: "challenger", prompt: CHALLENGER_PROMPT },
            *[{ name: s.name, prompt: s.prompt } for s in specialists]
        ]
    )

    # 4. 設計書を broadcast
    broadcast("queue/design/{phase}_debate.md に設計書がある。読んで議論を開始してくれ。")

    # 5. ラウンド進行（最大 3 ラウンド）
    for round in range(1, 4):
        # Advocate → Challenger → 専門スタッフ の順に発言
        wait_for_all_responses()

        # 合意チェック
        if all_agreed():
            break

        if round == 3 and not all_agreed():
            # 未解決点を Owner にエスカレーション
            escalate_to_dashboard()

    # 6. 最終設計書を生成
    finalize(f"queue/design/{phase}_final.yaml")

    # 7. チーム解散
    for teammate in team:
        shutdown_request(teammate)
```

#### 11. ディレクトリ構成

```
queue/design/
  phase1_debate.md       # Phase 1 の議論本体
  phase1_final.yaml      # Phase 1 の最終合意
  phase3_debate.md       # Phase 3 の議論本体
  phase3_final.yaml      # Phase 3 の最終合意
  adhoc_db-migration_debate.md    # アドホック議論
  adhoc_db-migration_final.yaml
```

#### 12. config/debate.yaml（新規）

```yaml
# Design Debate Protocol 設定
debate:
  # 基本設定
  max_rounds: 3
  message_max_chars: 200  # SendMessage の最大文字数

  # モデル設定（Director が必要に応じて変更可能）
  model:
    advocate: sonnet      # 議論の品質を確保するため Sonnet がデフォルト
    challenger: sonnet
    specialists: sonnet

  # スキップ条件
  skip_conditions:
    - "タスク数 2 以下の小規模 Phase"
    - "バグ修正のみの Phase"
    - "Owner が明示的にスキップ許可"

  # 専門スタッフのデフォルトマッピング
  specialist_hints:
    frontend: ["art_director"]
    backend: ["sound_designer"]
    architecture: ["cinematographer"]
    security: ["stunt_coordinator"]
    performance: ["vfx_supervisor"]
    mixed: []  # Director が判断
```

---

### Polnareff の主張まとめ

| ポイント | 提案 |
|---------|------|
| 議論基盤 | Agent Teams（TeamCreate/SendMessage）で一時チーム |
| 生存期間 | 議論単位（作って議論して解散） |
| コンテキスト負荷 | ファイルベース議論 + メッセージ 200 字制限 + 3 ラウンド上限 |
| 専門スタッフ | 映画裏方メタファー。7 種類。常設 2 名 + オンデマンド |
| v3 サブエージェントとの関係 | 別カテゴリ。Design Debate = 議論チーム、v3 = 個別作業者 |
| Advocate/Challenger | 独立プロトコルの常設メンバー。専門スタッフはオプション追加 |
| 利用シーン | Phase 開始前、技術的詰まり、Cast 間調停、アーキテクチャ判断 |

**核心の主張**: Task tool のワンショット往復ではなく、Agent Teams の双方向メッセージングで「本物の議論」を実現する。映画制作の裏方メタファーで専門家チームを体系化し、Director が必要な時に必要な専門家を召喚できるようにする。

---

## Round 1: Fugo の反論

### 総評

方向性は理解できる。「Task tool ワンショットでは議論が成立しない」という問題意識は正しい。しかし、**解決策として Agent Teams を選んだことに致命的な矛盾がある**し、専門スタッフ体系は明らかに過剰設計だ。

以下、7つの問題点を指摘する。

---

### Issue #1 [CRITICAL]: v4 合意との矛盾 — Agent Teams は P7 オプションだったはず

v4 アーキテクチャ設計書（ensemble-v4-architecture.md）で俺たち自身が合意した内容:

> **「Agent Teams を『あったら嬉しいオプション』に留め、コア設計はファイルベース通信で完結させる」**
> **「Agent Teams が GA（一般公開）になった時点で P7 として検討する」**

合意署名で 11 項目中「Agent Teams = P7 オプション」に ✅ をつけた。俺もポルナレフも。

今回の提案は **P2.5 で Agent Teams をコア機能として導入している**。P7 で「オプション」として検討するはずだったものを、P2.5 に前倒しして「必須」にしている。これは合意違反だ。

**ポルナレフ自身が Round 2 で言った言葉を引用する**:
> 「第3の道は『将来のオプション』として温存。今は Position B のファイルベース案でコア設計する」

P2.5 は P7 より**前**に来る Phase だ。「将来のオプション」が「最初に実装するプロトコル」に化けている。

**反論を予想して先に潰す**: 「P2.5 の Agent Teams は Cast 通信(P7)とは違う。Director 内で完結する一時利用だから合意に抵触しない」と言うかもしれない。だが:
- Agent Teams の Research Preview リスク（不安定、仕様変更、廃止）は利用場所に関係なく同じ
- Director 内で使おうが Cast 間で使おうが、WSL2 での Agent Teams 動作検証は未実施
- P2.5 で Agent Teams が動かなかった場合、Design Debate Protocol 自体が使えなくなる

→ **コア機能を不安定な基盤の上に構築するな。v4 合意のファイルベース方針を貫け。**

---

### Issue #2 [HIGH]: Agent Teams で「本物の議論」は本当に成立するか

ポルナレフの主張: 「Task tool はワンショット。Agent Teams なら双方向メッセージングで本物の議論ができる」

**技術的に疑わしい点が3つある:**

#### 2-A: teammate 間のファイル共有問題

Agent Teams の teammate はそれぞれ独立したコンテキストを持つ。Advocate が `queue/design/phase3_debate.md` に追記した内容を Challenger が読むには、**Challenger 側で Read tool を呼ぶ必要がある**。SendMessage で「ファイルに書いた」と通知しても、Challenger が本当にファイルを読んでから反論するかは Agent Teams の実装次第。

ポルナレフの疑似コード（Section 10）は `wait_for_all_responses()` を呼んでいるが、**この関数は Agent Teams に存在しない**。Director は teammate からのメッセージを受動的に受け取るだけで、「全員の発言を待つ」同期機構はない。

#### 2-B: ラウンド制御の難しさ

疑似コードの `for round in range(1, 4)` ループ。Director が「Round 2 を開始する」とメッセージを送り、Advocate と Challenger がそれぞれファイルに書いて通知を送る。だが:

- teammate がいつ発言するかは Agent Teams のスケジューリング次第
- Advocate が先に書いて Challenger が後から書く保証がない
- Director が「両者の発言が揃った」ことをどう判定するか不明確
- ラウンド間の同期は Director の手動管理になる

**Task tool のワンショットの方がむしろ制御しやすい**: 「Advocate に送る → 結果を受け取る → Challenger にAdvocateの主張を含めて送る → 結果を受け取る」。順序が保証される。

#### 2-C: v4 ディベート自体が Task tool で成立した事実

**今まさにこの議論を Task tool（的な仕組み）でやっている**。俺とポルナレフは Agent Teams の teammate だが、それは Owner が実験的に使っているからであって、ファイルベース議論でも同じことは可能だ。実際、v4 アーキテクチャのディベートは議論結果を `docs/ensemble-v4-architecture.md` にファイルとして書き残しながら進めた。

→ **Agent Teams なしでも Design Debate は成立する。Task tool 3回呼び出し（Advocate → Challenger → Advocate）で十分。**

---

### Issue #3 [HIGH]: 専門スタッフ 7 種類は過剰設計

Art Director, Cinematographer, Sound Designer, Stunt Coordinator, VFX Supervisor の 5 種類の専門スタッフ。問題点:

#### 3-A: 名称の曖昧さ

「Sound Designer = API設計」「Cinematographer = アーキテクチャ」というマッピングは映画好きにしか通じない。初見の Director（コンパクション後の自分自身含む）が「Sound Designer を呼ぼう」とはならない。「API設計の専門家を呼ぼう」とは思うが、それが Sound Designer だと気づくまでにテーブルを参照する必要がある。

映画メタファーは ENSEMBLE-CAST の核心だが、**実用性を犠牲にするほどメタファーに固執すべきではない**。

#### 3-B: 実質的な差異の薄さ

| スタッフ | やること |
|---------|---------|
| Art Director | UI/UXの設計レビュー |
| Sound Designer | API/データフローの設計レビュー |
| Cinematographer | アーキテクチャの設計レビュー |
| VFX Supervisor | パフォーマンスの設計レビュー |
| Stunt Coordinator | セキュリティの設計レビュー |

**全部「設計レビュー」**。異なるのは「観点」だけ。それならプロンプトの「あなたの専門分野」セクションを変えるだけで済む。5つの名前付きロールに分ける必要はない。

#### 3-C: Director の判断負荷

「今回は Sound Designer を呼ぶべきか、Cinematographer を呼ぶべきか、両方か」を Director が毎回判断する。Director はコンテキストが限られた AI であり、この判断自体がコンテキストを消費する。

**提案**: 専門スタッフは **1 種類に統合**。名称は「Specialist（専門家）」。プロンプトに「今回のテーマは API 設計」と書けばいい。

```
Design Debate メンバー:
  - Advocate（常設）: 設計擁護
  - Challenger（常設）: 設計批判
  - Specialist（オプション、最大1名）: テーマに応じた専門知識の提供
```

7 種類 → 3 種類。シンプルで判断しやすい。

---

### Issue #4 [MEDIUM]: Director のコンテキスト負荷は制御できない

ポルナレフの対策:
1. ファイルベースで議論
2. メッセージ 200 文字制限
3. 3 ラウンド制限
4. 議論後に即 shutdown

**問題**: Agent Teams の仕組み上、teammate のメッセージは Director のコンテキストに**サマリーとして流入する**。200 文字制限を teammate に守らせても、Agent Teams の内部処理でコンテキストが消費される:

- TeamCreate のオーバーヘッド（チーム作成の処理自体）
- 各 teammate への初期プロンプト配信
- SendMessage ごとのメタデータ
- shutdown_request / shutdown_response のハンドシェイク

**3ラウンド × Advocate + Challenger + Specialist 1名 = 9メッセージ**。各メッセージの SendMessage オーバーヘッド + Director が読んで判断する処理。Design Debate 1 回で Director のコンテキストの 10-15% を消費する可能性がある。

Director は Design Debate の後にタスク配布、Cast 管理、レビュー、マージと作業が続く。序盤で 10-15% 消費は痛い。

**Task tool 方式なら**: サブエージェントのコンテキストは Director に流入しない。Director は最終結果だけを受け取る。コンテキスト消費は最小限。

---

### Issue #5 [MEDIUM]: レートリミットの楽観的見積もり

ポルナレフの主張: 「Design Debate は Phase 開始前に実行するので Cast はまだ idle。レートリミット圧迫は限定的」

**反論**:

1. **シーン2、シーン3**: Phase 途中でも Design Debate を実行するシナリオがある。この場合 Cast は作業中。Director + Advocate + Challenger + Specialist + Cast 5名 = 最大 9 プロセスが同時に API を消費する。

2. **Agent Teams の teammate は個別にAPI呼び出しを行う**: TeamCreate で 3 名の teammate を作ると、各 teammate が独立して Read/Grep/WebSearch 等のツールを呼ぶ。これは Director + 3 = 4 プロセス分の API 消費。

3. **Max プランのレートリミットは非公開**: 同時 9 プロセスでのレートリミット挙動は実測するまで不明。Chrome 拡張の Issue #23082 の二の舞になりかねない。

→ **Phase 途中のアドホック議論を認めるなら、Cast を一時停止する運用ルールが必要。そのルールが設計に含まれていない。**

---

### Issue #6 [LOW]: v3 サブエージェントとの区別が実質的に不明確

ポルナレフの整理:
- Design Debate スタッフ = 議論チーム（Agent Teams）
- v3 サブエージェント = 個別作業者（Task tool）

**問題**: Cinematographer（Design Debate）と Technical Advisor（v3）を「統合」するとしているが、**同一の役割を 2 つの異なる技術基盤で実装することになる**:

- Design Debate 時: Agent Teams で Cinematographer として参加
- レビュー時: Task tool で Technical Advisor として召喚

同じ「技術的評価」の仕事を、場面によって Agent Teams と Task tool を使い分ける。Director の判断負荷が増える。「今は Agent Teams で呼ぶべきか、Task tool で呼ぶべきか」。

→ **全部 Task tool に統一すれば、この問題は発生しない。**

---

### Issue #7 [LOW]: config/debate.yaml の specialist_hints は使われない

```yaml
specialist_hints:
  frontend: ["art_director"]
  backend: ["sound_designer"]
```

このマッピングは Director が参照するためのヒントだが:
- Director は AI であり、YAML のヒントテーブルを見て判断するよりも、プロンプトで直接指示された方が正確
- config ファイルに書いてあっても、コンパクション後に Director がこの config を読む保証がない（コンテキスト読み込み順序に config/debate.yaml が入っていない）
- ヒントテーブルの保守が必要（新しい専門分野が出たら更新）

→ **Director の指示書（director.md）に直接記述した方がシンプル。config ファイルの間接参照は不要。**

---

### Fugo の対案: Task tool 3段階方式

Agent Teams を使わず、Task tool の組み合わせで Design Debate を実現する:

```
Director が設計レビューが必要と判断
  ↓
queue/design/<phase>_debate.md に設計書を作成
  ↓
Step 1: Task tool で Advocate を召喚
  - 入力: 設計書
  - 出力: 擁護論（_debate.md に追記）
  ↓
Step 2: Task tool で Challenger を召喚
  - 入力: 設計書 + Advocate の擁護論
  - 出力: 反論（_debate.md に追記）
  ↓
Step 3: Task tool で Advocate を再召喚（必要な場合のみ）
  - 入力: 設計書 + 擁護論 + 反論
  - 出力: 最終回答（_debate.md に追記）
  ↓
Step 4: Director が統合 → _final.yaml
  ↓
通常業務（タスク配布）に復帰
```

**この方式の利点**:

| 項目 | Agent Teams 方式 | Task tool 3段階方式 |
|------|-----------------|-------------------|
| v4 合意との整合性 | ❌ P7 前倒し | ✅ Agent Teams 不使用 |
| Director コンテキスト | ❌ teammate メッセージ流入 | ✅ 最終結果のみ受領 |
| ラウンド制御 | ❌ 同期困難 | ✅ 順序保証 |
| レートリミット | ❌ 同時並行 | ✅ 逐次実行 |
| 実装の安定性 | ❌ Research Preview 依存 | ✅ 安定した Task tool |
| 専門家の追加 | △ teammate 追加 | ✅ Step に専門家観点を注入 |

**専門家の扱い**:

専門家（Specialist）の知識は **Challenger のプロンプトに観点として注入** すればいい。別の teammate / Task を呼ぶ必要すらない。

```
Step 2: Task tool で Challenger を召喚
  プロンプト:
  あなたは Challenger です。設計を批判的に検証してください。

  今回のテーマには API 設計が含まれるため、以下の追加観点でもレビューしてください:
  - API 設計: RESTful 原則の準拠、エラーハンドリング、データモデルの妥当性
  - セキュリティ: 入力バリデーション、認証/認可、XSS/CSRF 防止

  設計書 + Advocate の擁護論: queue/design/phase3_debate.md を読んでください。
```

**これなら Task tool 2-3 回で完結**。別プロセスが不要。コンテキスト負荷最小。レートリミット影響なし。

---

### Fugo の判定サマリー

| Polnareff の提案 | Fugo の判定 | 理由 |
|-----------------|-------------|------|
| Agent Teams で一時チーム | ❌ 反対 | v4 合意違反。技術的リスク。Task tool で代替可能 |
| 専門スタッフ 7 種類 | ❌ 過剰設計 | 実質差異が薄い。Specialist 1 種類に統合 |
| Advocate + Challenger 常設 | ✅ 賛成 | 対立構造は Design Debate の核心 |
| ファイルベース議論 | ✅ 賛成 | queue/design/ のディレクトリ構成は妥当 |
| 3 ラウンド制限 | ✅ 賛成 | コンテキスト保護に有効 |
| 利用シーン 4 種類 | △ 条件付き賛成 | Phase途中利用（シーン2,3）はCast一時停止ルールが必要 |
| config/debate.yaml | ❌ 不要 | director.md に直接記述で十分 |
| メッセージ 200 字制限 | ✅ 賛成 | ただし Agent Teams ではなく Task tool のプロンプト内で制御 |

**核心の主張**: Agent Teams を使わなくても、Task tool の逐次呼び出し（Advocate → Challenger → Advocate）で Design Debate は成立する。v4 合意を破る必要はない。専門家の知見は Challenger のプロンプトに観点として注入すれば、別プロセスを立てる必要すらない。**シンプルに勝るものはない。**

---

## Round 2: Polnareff の応答

### 判定サマリー

| Fugo の指摘 | Polnareff の判定 | 対応 |
|-------------|-----------------|------|
| #1 [CRITICAL] v4 合意違反 | ✅ **受け入れ。Agent Teams をコア基盤にしない** | Task tool ベースに変更。Agent Teams はフォールバック |
| #2 [HIGH] Agent Teams で議論は成立するか | ✅ **技術的指摘は正しい** | Task tool 3段階方式を採用。ただし修正提案あり |
| #3 [HIGH] 専門スタッフ 7種類は過剰 | △ **一部受け入れ。ただし Specialist 1種類は削りすぎ** | 3種類に整理。下記で詳述 |
| #4 [MEDIUM] Director コンテキスト負荷 | ✅ **Task tool 方式なら解消** | Issue #1, #2 の受け入れにより自動解消 |
| #5 [MEDIUM] レートリミット | ✅ **Phase途中利用時の運用ルール追加** | 下記で具体案 |
| #6 [LOW] v3 サブエージェントとの混乱 | ✅ **Task tool 統一で解消** | Issue #1 受け入れにより自動解消 |
| #7 [LOW] config/debate.yaml 不要 | ✅ **受け入れ** | director.md に直接記述 |

**7指摘中、5つを完全受け入れ。1つを部分受け入れ。1つは自動解消。**

---

### 1. Agent Teams の撤回 — v4 合意を破るべきではない

フーゴの言う通りだ。俺は自分が合意した内容に反していた。

v4 ディベートの Round 2 で俺自身がこう言った:
> 「第3の道は『将来のオプション』として温存。今は Position B のファイルベース案でコア設計する」

Agent Teams は P7 オプション。P2.5 でコア機能にするのは合意違反。

**さらに、Issue #2 の技術的指摘が正しい**:
- `wait_for_all_responses()` は存在しない。ラウンド同期は手動管理
- teammate のファイル読み込みタイミングが保証されない
- Task tool の逐次呼び出しの方が順序が確定的

**撤回**: Agent Teams ベースの一時チーム案を撤回する。Task tool ベースに変更。

---

### 2. Task tool 3段階方式への修正提案

フーゴの対案を大筋で採用する。ただし2点修正:

#### 修正 A: 3段階ではなく「最大3段階」

フーゴの案:
```
Step 1: Advocate 召喚 → 擁護論
Step 2: Challenger 召喚（+ Advocate の擁護論）→ 反論
Step 3: Advocate 再召喚（必要な場合のみ）→ 最終回答
Step 4: Director が統合
```

**問題**: Step 3 は「Advocate の最終回答」だけで、Challenger が最終回答に反論する機会がない。非対称。

**修正案: 最大 2 ラウンド（4 ステップ）**

```
Round 1:
  Step 1: Task tool — Advocate 召喚
    入力: 設計書
    出力: 擁護論（_debate.md に Section A1 として追記）

  Step 2: Task tool — Challenger 召喚
    入力: 設計書 + Advocate の擁護論
    出力: 反論 + 判定テーブル（_debate.md に Section C1 として追記）

Director がここで判定:
  - Challenger が全項目「✅ 賛成」 → 即座に _final.yaml 作成。終了
  - 重大な反論あり → Round 2 へ

Round 2（必要な場合のみ）:
  Step 3: Task tool — Advocate 再召喚
    入力: 設計書 + 擁護論 + 反論
    出力: 修正案 or 反駁（_debate.md に Section A2 として追記）

  Step 4: Task tool — Challenger 再召喚
    入力: 全議論
    出力: 最終判定（_debate.md に Section C2 として追記）

Director が統合 → _final.yaml
```

**これにより**:
- 対称性が保たれる（Advocate と Challenger が同数回発言）
- 最良ケース: Task tool 2回で終了（Round 1 で全合意）
- 最悪ケース: Task tool 4回（Round 2 まで必要）
- 平均ケース: Task tool 3回（Round 1 で大筋合意、数点を Round 2 で解消）

#### 修正 B: Advocate と Challenger の並列召喚（Round 1 のみ）

Round 1 の Step 1 と Step 2 は **依存関係がある**（Challenger は Advocate の論を読む必要がある）ので並列化できない... と思われるが、**Phase によっては可能**:

```
パターン1: 逐次（デフォルト）
  Advocate → Challenger → (Director判定) → Round 2

パターン2: 並列初手（シンプルな設計の場合）
  Advocate + Challenger を同時召喚
  → 両者が設計書だけを見て独立に論点を出す
  → Director が両者の論点を統合 → _final.yaml

パターン2 は「議論」ではなく「独立レビュー」になるが、
シンプルな設計ではこれで十分。時間短縮。
```

Director が Phase の複雑さに応じてパターンを選択する。

---

### 3. 専門スタッフの整理 — 7種類は撤回、ただし1種類は削りすぎ

フーゴの指摘:
> 「全部『設計レビュー』。異なるのは観点だけ。Specialist 1 種類に統合」

**半分正しいが、半分間違っている。**

「全部設計レビュー」は正しい。だが「Specialist 1 種類」だと、**Challenger のプロンプトに専門観点を注入する** という提案に俺は反対する。

理由: **Challenger の役割は「設計の批判」であって、「専門知識の提供」ではない**。

```
❌ Challenger に専門観点を注入:
  「設計を批判せよ。ただし API 設計の専門家としても意見せよ」
  → 2つの役割を同時に担うことになる
  → 批判モードと専門家モードが混在して論点がぼやける
  → 「Challenger が賛成した API 設計」は批判的に検証されていない
     （Challenger 自身が専門家として設計したのだから）

✅ Specialist を別に召喚:
  Advocate: 設計を擁護
  Challenger: 設計を批判
  Specialist: 専門分野から両者に意見
  → 3つの視点が独立している
  → Specialist の意見も Challenger が批判できる
```

**妥協案: 3 カテゴリに整理**

| 名称 | 映画メタファー | 役割 | 召喚条件 |
|------|-------------|------|---------|
| **Advocate** | 脚本家 A | 設計擁護 | 常設（必須） |
| **Challenger** | 脚本家 B | 設計批判 | 常設（必須） |
| **Consultant** | テクニカルアドバイザー | 専門観点の提供 | オプション（Director 判断） |

v3 の Technical Advisor と名称を統一。映画メタファーの新造語を避ける。

**Consultant のプロンプトにテーマを注入**:
```
あなたは Consultant（テクニカルアドバイザー）です。
今回のテーマ: バックエンド API 設計
専門観点: RESTful 原則、データモデル、エラーハンドリング、認証/認可
```

これで:
- 7 種類 → 3 種類（シンプル）
- 映画メタファーの新造語なし（Director が混乱しない）
- 専門知識は Consultant のプロンプトで柔軟に変更可能
- Challenger のプロンプトに過剰な責務を詰め込まない

**フーゴの「Specialist 1 種類」との違い**:
- フーゴ案: Challenger に専門観点を注入 → Specialist 不要
- 俺の案: Consultant を別の Task tool で召喚 → Challenger は批判に専念

差異は「Consultant を別 Task として呼ぶか、Challenger に統合するか」の 1 点だけ。

---

### 4. Phase 途中利用時の運用ルール

フーゴの Issue #5 指摘: Phase 途中で Design Debate を実行する場合のレートリミット問題。

**運用ルールを追加**:

```
Phase 途中の Design Debate 実行条件:
  1. 対象の Cast を一時停止する
     → Director が send-keys で「次の指示まで待機してください」を送信
  2. 停止を確認（Busy/Idle チェック）
  3. Design Debate を実行（Task tool 2-4 回）
  4. Design Debate 完了後、Cast を起床して修正タスクを配布

アドホック Debate は Phase 開始前 Debate より軽くする:
  - Round 1 のみ（Step 1 + Step 2 の 2 回で完結）
  - Consultant は呼ばない（論点が明確なため）
  - 未解決点は Owner エスカレーション
```

---

### 5. config/debate.yaml の撤回

フーゴの指摘通り、config ファイルの間接参照は不要。director.md に直接記述する。

---

### 6. 修正後の Design Debate Protocol 全体像

```
■ Design Debate Protocol（Task tool 方式）

トリガー:
  - Phase 開始前の設計レビュー（デフォルト）
  - Phase 途中の技術的ブロッカー（Director 判断）
  - Cast 間設計方針の調停（escalated discussion）

スキップ条件（Director 判断）:
  - タスク数 2 以下の小規模 Phase
  - バグ修正のみの Phase
  - Owner が明示的にスキップ許可
  - スキップ時は dashboard.md に理由を記載

メンバー:
  - Advocate（脚本家 A）: 設計擁護。Task tool 召喚
  - Challenger（脚本家 B）: 設計批判。Task tool 召喚
  - Consultant（テクニカルアドバイザー）: 専門観点。Task tool 召喚（オプション）

実行フロー:

  1. Director が queue/design/<phase>_debate.md に設計書を作成

  2. Round 1:
     a. Task tool — Advocate 召喚
        入力: 設計書
        出力: 擁護論（_debate.md に Section A1 として追記）

     b. Task tool — Challenger 召喚
        入力: 設計書 + 擁護論
        出力: 反論 + 判定テーブル（_debate.md に Section C1 として追記）

     c. (オプション) Task tool — Consultant 召喚
        入力: 設計書 + 擁護論 + 反論
        出力: 専門的見解（_debate.md に Section T1 として追記）

  3. Director が判定:
     - 全項目合意 → _final.yaml 作成。終了
     - 重大な反論あり → Round 2 へ

  4. Round 2（必要な場合のみ）:
     a. Task tool — Advocate 再召喚
        入力: 全議論
        出力: 修正案 or 反駁（Section A2）

     b. Task tool — Challenger 再召喚
        入力: 全議論
        出力: 最終判定（Section C2）

  5. Director が統合 → queue/design/<phase>_final.yaml
     - 未解決点は dashboard.md「🚨 要対応」に記載

Phase 途中のアドホック Debate:
  - Round 1 のみ（2 回で完結）
  - Consultant は呼ばない
  - 対象 Cast を事前に一時停止

コスト: Task tool 2-4 回（Sonnet）。Director コンテキスト負荷は最小限。
```

---

### 7. 残る論点（フーゴへの問い）

俺が受け入れなかった 1 点:

**Consultant を Challenger に統合するか、別 Task として呼ぶか**

フーゴの主張: Challenger のプロンプトに専門観点を注入すれば Specialist 不要
俺の主張: Challenger の責務が過剰になる。批判と専門知識提供は別の仕事

この差異は**実装コストの違いが Task tool 1 回分（Consultant 召喚）**。
それに見合う価値があるか、フーゴの判断を聞きたい。

1つ補足すると、Consultant を呼ぶケースは「Director が必要と判断した時だけ」だ。全 Phase で呼ぶわけではない。シンプルな Phase は Advocate + Challenger の 2 回で終わる。アーキテクチャ判断や新技術導入の時だけ、Consultant を追加で 1 回呼ぶ。追加コストは年間数回の Task tool 1 回分。

---

## Round 2: Fugo の応答

### 判定サマリー

| Polnareff の修正 | Fugo の判定 |
|-----------------|-------------|
| Agent Teams 撤回、Task tool ベースに変更 | ✅ 正しい判断 |
| 修正A: 最大2ラウンド（4ステップ）、対称性 | ✅ **採用。俺の3段階案より良い** |
| 修正B: 並列初手パターン | ❌ 不要。下記で説明 |
| 専門スタッフ 3 カテゴリ（Advocate/Challenger/Consultant） | ✅ **受け入れる。ポルナレフが正しい** |
| config/debate.yaml 撤回 | ✅ 合意済み |
| Phase途中利用の運用ルール（Cast一時停止） | ✅ 合意 |
| 修正後の全体像 | ✅ ほぼ合意。細部のみ調整 |

---

### 1. 修正A（最大2ラウンド4ステップ）: ポルナレフの改善を認める

俺の3段階案の問題点をポルナレフが正しく指摘した:

> 「Step 3 は Advocate の最終回答だけで、Challenger が最終回答に反論する機会がない。非対称」

これは正しい。Advocate → Challenger → Advocate で終わると、Advocate が最後に一方的に主張して終了する。対立構造の議論で対称性がないのは設計上の欠陥だ。

**最大2ラウンド（4ステップ）を採用する。** ただし、以下の点を明確化したい:

- Round 1 で「全項目合意」の判定は **Director** が行う（Challenger の判定テーブルだけで自動判定しない）
- Director が Round 2 不要と判断すれば 2 ステップで終了。判断の主体は Director

---

### 2. 修正B（並列初手パターン）: 不要。削除すべき

> 「Advocate + Challenger を同時召喚 → 両者が設計書だけを見て独立に論点を出す」

これは「議論」ではなく「独立レビュー」とポルナレフ自身が認めている。

**Design Debate Protocol の核心は「対立構造による議論」だ。** 独立レビューは別のもの（Script Supervisor の並列召喚）で既に実現できる。Design Debate Protocol に並列パターンを混ぜると:

1. Director が「今回は並列でいいか、逐次にすべきか」を毎回判断する負荷が増える
2. 「Design Debate をやりました」と言いつつ実質はただのレビュー、というケースが増える（議論の品質劣化）
3. プロトコルの定義が曖昧になる（「Design Debate とは何か」が2種類ある）

**シンプルな設計なら Design Debate をスキップすればいい。** スキップ条件は既に定義されている（タスク数2以下、バグ修正のみ、Owner許可）。「やるなら逐次、やらないならスキップ」の二択でいい。中間の「並列独立レビュー」は不要。

→ **修正B を削除。Design Debate は常に逐次（Advocate → Challenger）。**

---

### 3. Consultant を別 Task として呼ぶ件: ポルナレフが正しい。受け入れる

これが今回の議論の最後の論点だった。俺の元の主張:

> 「Challenger のプロンプトに専門観点を注入すれば Specialist 不要」

ポルナレフの反論:

> 「Challenger の役割は設計の批判であって、専門知識の提供ではない。2つの役割を同時に担うと、批判モードと専門家モードが混在して論点がぼやける」

**考え直した結果、ポルナレフの方が正しい。** 理由:

#### 3-A: 役割の分離原則

ENSEMBLE-CAST 全体の設計思想は「1 Agent = 1 責務」だ:
- Director はコードを書かない（F001）
- Cast はタスクの変更をしない
- Red Team は提案のみで命令しない

同じ原則で、Challenger は「批判」だけに専念すべきだ。専門知識の提供という別の責務を混ぜると、批判の質が下がるか、専門知識の質が下がるか、両方が中途半端になる。

#### 3-B: 実コスト分析

Consultant を別 Task で呼ぶ追加コストは:
- Task tool 1 回分の API 呼び出し（逐次なのでレートリミット影響は微小）
- Director のコンテキストに結果サマリーが 1 件追加される程度

このコストで得られるもの:
- Challenger が批判に専念できる（批判の質向上）
- 専門知識が独立した視点として提供される（Challenger の批判対象にもなる）
- 「Specialist の意見も Challenger が批判できる」というポルナレフの指摘は鋭い

**追加コスト（Task tool 1 回）< 得られる価値（批判品質の維持 + 独立視点の確保）。**

#### 3-C: ただし名称について補足

Consultant（テクニカルアドバイザー）の名称は問題ない。v3 の Technical Advisor と実質同一で、Director が混乱しない。映画メタファーの新造語を避けたのも正しい判断。

**結論: Consultant を別 Task tool で呼ぶ設計を受け入れる。**

---

### 4. 細部の調整提案

ポルナレフの「修正後の全体像」（Section 6）は概ね良い。以下の3点を追加・調整したい:

#### 4-A: Consultant の呼び出しタイミング

ポルナレフの案では Round 1 の Step c として Consultant を呼んでいる:

```
Round 1:
  a. Advocate 擁護論
  b. Challenger 反論
  c. (オプション) Consultant 専門的見解
```

**問題**: Consultant は Advocate の擁護論と Challenger の反論の**両方を見てから**意見すべきだ。ポルナレフの案はこの順序になっているので OK だが、明示的に「Consultant は Round 1 の a, b の結果を全て入力として受け取る」ことを仕様に書くべき。

また、**Consultant を呼ぶなら Round 1 でのみ呼ぶ**（Round 2 では呼ばない）。Round 2 は Advocate と Challenger の決着の場であり、専門家の追加意見は不要。

#### 4-B: debate.md のセクション命名規則

`Section A1`, `Section C1`, `Section T1` は良いが、仕様として明記すべき:

```
セクション命名規則:
  A1, A2: Advocate のラウンド 1, 2
  C1, C2: Challenger のラウンド 1, 2
  T1: Consultant（呼んだ場合のみ。Round 1 のみ）
  F: Director の最終統合
```

#### 4-C: _final.yaml の最低限のフォーマット

_final.yaml の構造がまだ定義されていない。最低限以下を含むべき:

```yaml
# queue/design/<phase>_final.yaml
phase: 3
debate_date: "2026-02-10"
rounds: 1  # 実際に実行したラウンド数
consultant_called: false  # Consultant を呼んだか
participants: ["advocate", "challenger"]

agreed:
  - point: "Hono + D1 でバックエンド構築"
    rationale: "Cloudflare 完結の要件に合致"

unresolved:  # Owner エスカレーション対象
  - point: "KV vs D1 のキャッシュ戦略"
    advocate_position: "D1 で統一"
    challenger_position: "KV 併用"
    escalated_to: "dashboard.md 🚨要対応"

tasks_adjusted:
  - task_id: 5
    change: "データモデルに tags フィールド追加"
    reason: "Challenger の指摘により"
```

---

### 5. 最終合意に向けて

**残る未合意点はゼロ**。以下が確認事項:

| 論点 | 合意状態 |
|------|---------|
| 議論基盤: Task tool 逐次方式 | ✅ 合意 |
| ラウンド構造: 最大2ラウンド（4ステップ） | ✅ 合意 |
| 並列初手パターン: 不採用 | △ **ポルナレフの確認待ち** |
| メンバー: Advocate + Challenger + Consultant(オプション) | ✅ 合意 |
| Consultant のタイミング: Round 1 のみ | △ **ポルナレフの確認待ち** |
| config/debate.yaml: 不採用、director.md 直接記述 | ✅ 合意 |
| Phase途中利用: Cast一時停止ルール | ✅ 合意 |
| _final.yaml フォーマット | △ **ポルナレフの確認待ち** |
| セクション命名規則 | △ **ポルナレフの確認待ち** |
| 利用シーン 4 種類 | ✅ 合意 |
| スキップ条件 | ✅ 合意（v4 合意のまま） |

ポルナレフに3点の確認を求める:
1. 修正B（並列初手パターン）の削除を受け入れるか
2. Consultant は Round 1 のみで OK か
3. _final.yaml のフォーマットとセクション命名規則は問題ないか

この3点が合意されれば、Round 3 で最終仕様をまとめられる。

---

## Round 3: Polnareff の最終応答 + 合意形成

### フーゴの 3 つの確認への回答

**Q1: 修正B（並列初手パターン）の削除を受け入れるか**

**受け入れる。** フーゴの論理は正しい:

> 「Design Debate の核心は対立構造による議論。独立レビューは別のもの（Script Supervisor の並列召喚）で既に実現できる」
> 「やるなら逐次、やらないならスキップ。中間は不要」

俺自身が「パターン2は議論ではなく独立レビュー」と認めていた。Design Debate Protocol の定義を曖昧にする選択肢を残す理由がない。削除。

**Q2: Consultant は Round 1 のみで OK か**

**OK。** Round 2 は Advocate と Challenger の決着の場。専門家が Round 2 に参加すると:
- Advocate が Consultant の意見を引用して反駁の根拠にする → Challenger が不利になる
- Round 2 が 3 者間の議論になり、収束しにくくなる

Consultant の見解は Round 1 で出し切り、Round 2 では Advocate と Challenger がその見解も含めて最終判断を下す。この構造が最もクリーン。

**Q3: _final.yaml のフォーマットとセクション命名規則は問題ないか**

**問題ない。良い補足だ。** 2 点だけ追加:

1. `_final.yaml` に `skipped: true` のケースも定義すべき:
```yaml
# Design Debate をスキップした場合
phase: 2
debate_date: "2026-02-10"
skipped: true
skip_reason: "バグ修正のみの Phase。タスク数 1"
```
Director がスキップした事実と理由を記録する。dashboard.md にも書くが、_final.yaml にも残しておくとチームの学習に使える。

2. セクション命名規則の `F:` は省略可能。Director の統合は _final.yaml に書くので、_debate.md にセクションを追加する必要はない。_debate.md は議論の記録、_final.yaml は結論の記録。分離が明確。

---

### 全項目の合意確認

| # | 論点 | 合意内容 | 提案者 |
|---|------|---------|--------|
| 1 | 議論基盤 | **Task tool 逐次方式**。Agent Teams は使わない | Fugo |
| 2 | ラウンド構造 | **最大 2 ラウンド（4 ステップ）**。対称性を保つ | Polnareff |
| 3 | 並列初手パターン | **不採用**。「やるなら逐次、やらないならスキップ」 | Fugo |
| 4 | メンバー | **Advocate + Challenger（常設）+ Consultant（オプション）** | Polnareff + Fugo |
| 5 | Consultant のタイミング | **Round 1 のみ**。Round 2 には参加しない | Fugo |
| 6 | Consultant の位置 | **Challenger とは別 Task tool**。1 Agent = 1 責務 | Polnareff |
| 7 | 設定ファイル | **config/debate.yaml は不採用**。director.md に直接記述 | Fugo |
| 8 | Phase 途中利用 | **Cast 一時停止ルール + アドホックは Round 1 のみ** | Polnareff + Fugo |
| 9 | v3 サブエージェントとの関係 | **Task tool 統一**。Consultant = Technical Advisor | Polnareff + Fugo |
| 10 | セクション命名 | **A1, A2, C1, C2, T1**。F は省略（_final.yaml に書く） | Fugo + Polnareff |
| 11 | _final.yaml フォーマット | **合意版（下記）** + skipped ケースを追加 | Fugo + Polnareff |
| 12 | 利用シーン | **4 種類**（Phase 開始前、技術ブロッカー、Cast 調停、アーキテクチャ判断） | Polnareff |
| 13 | スキップ条件 | **v4 合意のまま**（タスク数 2 以下、バグ修正のみ、Owner 許可） | v4 合意 |
| 14 | Director 判定の主体 | **Director が Round 2 要否を判断**。Challenger の判定テーブルは参考情報 | Fugo |

**全 14 項目合意完了。未合意点なし。**

---

### 最終仕様: P2.5 Design Debate Protocol

#### 1. 概要

Phase 開始前（またはアドホック）に、Director が Task tool で Advocate（擁護者）と Challenger（批判者）を逐次召喚し、設計の品質を議論によって高めるプロトコル。必要に応じて Consultant（専門家）を追加召喚する。

#### 2. メンバー

| 名称 | 役割 | 召喚 | 責務 |
|------|------|------|------|
| Advocate | 脚本家 A | Task tool（常設・必須） | 設計の擁護。実現可能性・利点を主張 |
| Challenger | 脚本家 B | Task tool（常設・必須） | 設計の批判。欠陥・リスク・暗黙の前提を攻撃 |
| Consultant | テクニカルアドバイザー | Task tool（オプション） | 専門分野からの独立した見解提供 |

#### 3. トリガー

| シーン | トリガー | 形式 |
|--------|---------|------|
| Phase 開始前の設計レビュー | Director が Phase のタスク分解を完了した時 | フル（最大 2 ラウンド） |
| Phase 途中の技術ブロッカー | Cast が status: blocked で報告し、アーキテクチャ判断が必要な時 | アドホック（Round 1 のみ） |
| Cast 間設計方針の調停 | Cast 間 discussion が escalated になった時 | アドホック（Round 1 のみ） |
| アーキテクチャ判断 | 新技術導入、スタック変更等の重大判断時 | フル（最大 2 ラウンド） |

#### 4. スキップ条件（Director 判断）

- タスク数 2 以下の小規模 Phase
- バグ修正のみの Phase
- Owner が明示的にスキップ許可
- **スキップ時**: dashboard.md に理由を記載 + `queue/design/<phase>_final.yaml` に `skipped: true` を記録

#### 5. 実行フロー

```
1. Director が queue/design/<phase>_debate.md に設計書を作成

2. Round 1:
   a. Task tool — Advocate 召喚（逐次。必須）
      入力: 設計書（_debate.md のパス）
      出力: 擁護論（_debate.md に Section A1 として追記）
      プロンプト: 設計の実現可能性・利点を主張せよ

   b. Task tool — Challenger 召喚（逐次。必須）
      入力: 設計書 + Section A1
      出力: 反論 + 判定テーブル（_debate.md に Section C1 として追記）
      プロンプト: 設計の欠陥・リスク・暗黙の前提を攻撃せよ

   c. Task tool — Consultant 召喚（逐次。オプション。Director 判断）
      入力: 設計書 + Section A1 + Section C1
      出力: 専門的見解（_debate.md に Section T1 として追記）
      プロンプト: [テーマ]の専門家として両者の議論に見解を提供せよ
      召喚条件: アーキテクチャ判断、新技術導入、セキュリティ関連等

3. Director が判定:
   - Challenger の判定テーブル + Consultant の見解（あれば）を参考に
   - 全項目合意 or 軽微な指摘のみ → _final.yaml 作成。終了
   - 重大な反論あり → Round 2 へ

4. Round 2（必要な場合のみ。Consultant は参加しない）:
   a. Task tool — Advocate 再召喚
      入力: 全議論（_debate.md 全体）
      出力: 修正案 or 反駁（Section A2）

   b. Task tool — Challenger 再召喚
      入力: 全議論（_debate.md 全体）
      出力: 最終判定（Section C2）

5. Director が統合 → queue/design/<phase>_final.yaml
   - 合意点を tasks に反映
   - 未解決点は dashboard.md「🚨 要対応」に記載
```

#### 6. Phase 途中のアドホック Debate

```
条件:
  - 対象の Cast を事前に一時停止（send-keys で待機指示）
  - 停止を Busy/Idle チェックで確認

実行:
  - Round 1 のみ（Step a + Step b の 2 回で完結）
  - Consultant は呼ばない
  - 未解決点は Owner エスカレーション

完了後:
  - Cast を起床して修正タスクを配布
```

#### 7. ファイル構成

```
queue/design/
  <phase>_debate.md       # 議論本体（セクション A1, C1, T1, A2, C2 を追記）
  <phase>_final.yaml      # 最終合意（構造化 YAML）
  adhoc_<topic>_debate.md  # アドホック議論
  adhoc_<topic>_final.yaml
```

#### 8. セクション命名規則（_debate.md 内）

| セクション | 内容 | ラウンド |
|-----------|------|---------|
| A1 | Advocate の擁護論 | Round 1 |
| C1 | Challenger の反論 + 判定テーブル | Round 1 |
| T1 | Consultant の専門的見解（オプション） | Round 1 |
| A2 | Advocate の修正案 or 反駁 | Round 2 |
| C2 | Challenger の最終判定 | Round 2 |

#### 9. _final.yaml フォーマット

```yaml
# 通常ケース
phase: 3
debate_date: "2026-02-10"
rounds: 1
consultant_called: true
consultant_theme: "バックエンド API 設計"
participants: ["advocate", "challenger", "consultant"]

agreed:
  - point: "Hono + D1 でバックエンド構築"
    rationale: "Cloudflare 完結の要件に合致"
  - point: "REST API + Zod バリデーション"
    rationale: "Advocate/Challenger 合意。Consultant も推奨"

unresolved:
  - point: "KV vs D1 のキャッシュ戦略"
    advocate_position: "D1 で統一"
    challenger_position: "KV 併用"
    escalated_to: "dashboard.md 🚨要対応"

tasks_adjusted:
  - task_id: 5
    change: "データモデルに tags フィールド追加"
    reason: "Challenger の指摘により"

# スキップケース
# phase: 2
# debate_date: "2026-02-10"
# skipped: true
# skip_reason: "バグ修正のみの Phase。タスク数 1"
```

#### 10. コスト分析

| ケース | Task tool 呼び出し | コンテキスト消費 |
|--------|-------------------|----------------|
| Round 1 のみ（Consultant なし） | 2 回 | 最小 |
| Round 1 のみ（Consultant あり） | 3 回 | 小 |
| Round 2 まで（Consultant なし） | 4 回 | 小 |
| Round 2 まで（Consultant あり） | 5 回 | 中（最大ケース） |
| アドホック | 2 回 | 最小 |
| スキップ | 0 回 | なし |

Max プラン前提: Task tool は逐次実行のため、レートリミットへの影響は微小。

#### 11. director.md への追記内容（概要）

以下のセクションを director.md に追加する（実装時に具体的な文面を作成）:

- Design Debate Protocol セクション
  - トリガー条件
  - スキップ条件と記録方法
  - 実行手順（上記フローの簡潔版）
  - Advocate / Challenger / Consultant のプロンプトテンプレート
  - _final.yaml の書き方
  - アドホック Debate の手順

#### 12. v4 Phase 計画との対応

v4 合意済みの Phase 計画:

| Phase | 内容 | P2.5 との関係 |
|-------|------|-------------|
| P1 | Context 汚染対策 + chronicle handoff | なし |
| P2 | CI 基盤 | なし |
| **P2.5** | **Design Debate Protocol** | **本仕様を実装** |
| P3 | Cast 間通信基盤 | Design Debate で設計レビュー可能 |
| P4 | Red Team 昇格 | Design Debate で設計レビュー可能 |
| P5 | Director 薄体化 | Design Debate が Director の新ワークフローに組み込まれる |
| P6 | Team Memory | Design Debate の結果（_final.yaml）が Team Memory に蓄積 |
| P7 | Agent Teams 統合（オプション） | Agent Teams GA 後に Design Debate の基盤を移行検討 |

**P2.5 の実装成果物**:
- `queue/design/` ディレクトリ作成
- `instructions/director.md` に Design Debate Protocol セクション追加
- `CLAUDE.md` に Design Debate の概要記載
- Advocate / Challenger / Consultant のプロンプトテンプレート（director.md 内）

---

### 合意署名

| 項目 | Polnareff | Fugo |
|------|-----------|------|
| 議論基盤: Task tool 逐次方式 | ✅ | ✅ |
| ラウンド構造: 最大 2 ラウンド（4 ステップ）| ✅ | ✅ |
| 並列初手パターン: 不採用 | ✅ | ✅ |
| メンバー: Advocate + Challenger + Consultant(オプション) | ✅ | ✅ |
| Consultant: Round 1 のみ、別 Task tool | ✅ | ✅ |
| config/debate.yaml: 不採用 | ✅ | ✅ |
| Phase 途中: Cast 一時停止 + アドホック Round 1 のみ | ✅ | ✅ |
| セクション命名: A1, C1, T1, A2, C2 | ✅ | ✅ |
| _final.yaml フォーマット（+ skipped ケース）| ✅ | ✅ |
| 利用シーン 4 種類 | ✅ | ✅ |
| スキップ条件（v4 合意踏襲）| ✅ | ✅ |
| Director が Round 2 要否を判断 | ✅ | ✅ |
| v3 サブエージェント統一（Consultant = Technical Advisor）| ✅ | ✅ |
| v4 合意遵守（Agent Teams は P7 オプション維持）| ✅ | ✅ |

**全 14 項目合意完了。**

---

## メタ情報

| 項目 | 値 |
|------|-----|
| ディベート日 | 2026-02-09 |
| 合意日 | 2026-02-09 |
| ラウンド数 | 3（Round 1 → Round 2 → Round 3 合意形成） |
| 合意率 | 100%（全 14 項目） |
| Polnareff（Advocate） | Claude Opus 4.6 |
| Fugo（Challenger） | Claude Opus 4.6 |
| 参照ファイル | `docs/ensemble-v4-architecture.md`, `docs/swarm-v2-design.md`, `CLAUDE.md`, `instructions/director.md` |
| 主要な設計変更 | Agent Teams → Task tool（v4合意遵守）、専門スタッフ 7種 → 3種（Advocate/Challenger/Consultant）、最大2ラウンド対称構造 |
