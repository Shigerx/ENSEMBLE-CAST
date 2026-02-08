# Theater v3 — 映画演出エンジン設計書

> せっかく脚本が最高なのに、文字を表示するだけではもったいない。
> Theater は映画館。観客が息を呑む演出で脚本の魅力を何倍にも増幅する。

---

## 問題

| 現状 | 原因 |
|------|------|
| 脚本の質は高いのに、観る体験が淡白 | テキストサイズが全部 `text-sm` で均一。メリハリがない |
| アニメーションがほぼ気づかない | fade 0.5-1秒だけ。ブラウザの表現力を使い切っていない |
| シーン転換に映画的な「間」がない | シーンが `---- ☕ ----` で区切られるだけ |
| キャラのセリフに重みがない | emoji + 名前 + 「セリフ」 がフラットに並ぶ |
| FIN が呆気ない | 小さい文字でフェードインするだけ |
| 「映画を観ている」感覚にならない | 全体的にブログ記事の読書体験に近い |

### 根本方針

**Theater は「テキストビューア」ではなく「映画上映エンジン」。**
脚本のドラマを視覚演出で何倍にも増幅する。

---

## コンセプト: アニメ映画のプレミア上映

```
v2 Theater = 電子書籍（テキストをスクロールして読む）
v3 Theater = 映画上映（演出が脚本を引き立てる）
```

3原則:

1. **タイポグラフィの緩急** — フォントサイズ・ウェイト・間隔で視覚リズムを作る
2. **シネマティック・トランジション** — シーン転換を映画的に演出する
3. **キャラクター演出** — セリフの見せ方でキャラの存在感を増幅する

---

## タイポグラフィ設計（最重要）

v2 は全要素が `text-sm`（14px）。v3 では階層を明確にする。

### フォントサイズ階層

| 要素 | v2 | v3 | 演出意図 |
|------|----|----|---------|
| エピソードタイトル | text-2xl (24px) | **text-5xl (48px)** | 映画タイトルは大きく堂々と |
| シーンタイトル | text-sm (14px) | **text-2xl (24px)** | チャプターの始まりを明確に |
| ナレーション | text-sm (14px) | **text-lg (18px)** italic | 語り部の声。大きめで落ち着いた書体 |
| キャラ名 | text-sm (14px) | **text-xl (20px)** bold | 誰が喋るか一目でわかる |
| セリフ本文 | text-sm (14px) | **text-2xl〜3xl (24-30px)** | セリフは主役。一番大きく |
| ト書き（action） | text-xs (12px) | **text-sm (14px)** dim italic | 控えめだが視認できる |
| シーンブレイク | text-sm (14px) | **装飾的区切り** | テキストではなくビジュアルで |
| FIN | text-xl (20px) | **text-6xl (60px)** | 圧倒的な余韻 |

### 重要セリフの強調（Dramatic Line）

脚本の `dramatic: true` フラグがあるセリフ、またはシーン最後のセリフを特別演出:

```css
/* 通常セリフ */
.dialogue { font-size: 1.5rem; color: rgba(255,255,255,.85); }

/* ドラマティックセリフ */
.dialogue-dramatic {
  font-size: 2rem;
  color: #fff;
  text-shadow: 0 0 30px rgba(240,192,64,.4);
  letter-spacing: .05em;
}
```

---

## シーン・トランジション

### Opening（エピソード開始）

```
[3秒] 暗転
[1秒] 「Episode N」が小さく中央にフェードイン
[0.5秒] タイトルが大きく展開（scale .8 → 1.0 + letter-spacing 広がる）
[1秒] サブタイトル（synopsis）がフェードイン
[0.5秒] 金色の線が左右に伸びる
[スクロール可能に]
```

```css
@keyframes title-reveal {
  0% { opacity: 0; transform: scale(.8); letter-spacing: .1em; }
  60% { opacity: 1; transform: scale(1.02); letter-spacing: .15em; }
  100% { opacity: 1; transform: scale(1); letter-spacing: .12em; }
}

@keyframes subtitle-rise {
  from { opacity: 0; transform: translateY(20px); filter: blur(4px); }
  to { opacity: 1; transform: translateY(0); filter: blur(0); }
}
```

### Scene Transition（シーン間）

v2: `---- ☕ ----`（テキスト）
v3: **シネマティック・ワイプ**

```
[現在のシーンの最後の要素表示]
[1.5秒] 画面が暗くなる（vignette 強化 + brightness down）
[0.5秒] 金色の光が中央から左右に広がる（horizontal wipe）
[0.3秒] 新しいシーンタイトルが中央にフラッシュ表示
[0.5秒] 新しいシーンの内容がフェードイン
```

```css
@keyframes scene-wipe {
  0% { width: 0; opacity: 0; }
  30% { width: 60%; opacity: 1; }
  70% { width: 100%; opacity: 1; }
  100% { width: 100%; opacity: 0; }
}

.scene-transition-line {
  height: 2px;
  background: linear-gradient(90deg, transparent, #f0c040, transparent);
  animation: scene-wipe 1.5s ease-in-out;
}
```

### 最終シーン（FINAL SCENE）

通常シーンより演出を強化:
- シーンタイトルが金色 + グロー
- 背景にかすかな金色のグラデーション追加
- 最後のセリフは `dialogue-dramatic` 扱い

---

## キャラクター演出

### セリフブロック（v3）

v2:
```
🌟 ジョルノ: (静かに立ち上がる)
  「トップページは僕が引き受けます。...これが、僕の『覚悟』です」
```

v3:
```
┌──────────────────────────────────────────────┐
│                                              │
│  🌟 ジョルノ・ジョバァーナ                    │  ← text-xl, キャラカラー
│  静かに立ち上がる                             │  ← text-sm, italic, dim
│                                              │
│  「トップページは僕が引き受けます。           │  ← text-2xl
│   ...これが、僕の『覚悟』です」               │  ← text-2xl, 左側にキャラカラーのバー
│                                              │
└──────────────────────────────────────────────┘
```

### キャラカラーバー

各キャラのセリフブロックの左端に、キャラカラーの縦線を配置:

```css
.beat-block {
  border-left: 3px solid var(--char-color);
  padding-left: 1.5rem;
  margin-bottom: 2rem;
}
```

これによりセリフの「持ち主」が色で直感的にわかる。

### キャラ名の登場アニメーション

各シーンでキャラが初めて喋る時、名前がスライドイン + グロー:

```css
@keyframes char-entrance {
  0% { opacity: 0; transform: translateX(-30px); }
  50% { opacity: 1; text-shadow: 0 0 20px var(--char-color); }
  100% { opacity: 1; transform: translateX(0); text-shadow: none; }
}
```

同じシーン内で2回目以降は通常フェードイン（初回のみ派手に）。

### セリフのタイプライター風表示（オプション・Auto Play モード用）

Auto Play モードでは、セリフを1文字ずつ表示:

```javascript
// Auto Play 時のみ有効
function typewriterEffect(element, text, speed = 30) {
  let i = 0;
  const timer = setInterval(() => {
    element.textContent += text[i];
    i++;
    if (i >= text.length) clearInterval(timer);
  }, speed);
}
```

**通常（スクロール）モードではタイプライターは使わない。** 読む速度を妨げるため。

---

## ナレーション演出

### ナレーションブロック（v3）

v2: italic text-sm で控えめ表示
v3: **映画のナレーション風**

```css
.narration-block {
  font-size: 1.125rem;        /* text-lg */
  font-style: italic;
  color: #a0aec0;
  line-height: 1.8;
  text-align: center;         /* 中央寄せ */
  max-width: 36rem;           /* 幅を絞って読みやすく */
  margin: 2rem auto;
  padding: 1.5rem 0;
  position: relative;
}

/* 上下に装飾線 */
.narration-block::before,
.narration-block::after {
  content: '';
  display: block;
  width: 60px;
  height: 1px;
  background: rgba(160,174,192,.3);
  margin: 0 auto 1rem;
}
.narration-block::after {
  margin: 1rem auto 0;
}
```

### ナレーション登場アニメーション

```css
@keyframes narration-reveal {
  from {
    opacity: 0;
    transform: translateY(15px);
    filter: blur(3px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
    filter: blur(0);
  }
}
```

ナレーションは blur からの解像で「語り部が話し始める」感覚を演出。

---

## FIN 演出

v2: `text-xl` で "FIN" とフェードイン
v3: **映画のエンディング**

### シーケンス

```
[最後のセリフ表示後]
[2秒] 余韻の間
[1秒] 画面が暗転（brightness → 0.3）
[0.5秒] 金色の横線が中央から広がる
[1秒] 「FIN」が巨大文字（text-6xl）でフェードイン + グロー
[0.5秒] 「Episode N — {title}」がその下にフェードイン
[3秒] 余韻
[フェード] エピソード一覧に戻るボタンが出現
```

```css
@keyframes fin-grand {
  0% { opacity: 0; transform: scale(.7); letter-spacing: .3em; }
  40% { opacity: 1; transform: scale(1.05); letter-spacing: .5em; }
  100% {
    opacity: 1;
    transform: scale(1);
    letter-spacing: .4em;
    text-shadow: 0 0 60px rgba(240,192,64,.5), 0 0 120px rgba(240,192,64,.2);
  }
}

.fin-grand {
  font-size: 3.75rem;  /* text-6xl */
  font-weight: 300;
  color: #f0c040;
  animation: fin-grand 2s ease-out both;
}
```

### FIN パーティクル（Canvas）

FIN 表示と同時に、金色のパーティクルが画面を漂う:

```javascript
// 軽量パーティクル（20-30個程度）
class GoldParticle {
  constructor(canvas) {
    this.x = Math.random() * canvas.width;
    this.y = canvas.height + 10;
    this.size = Math.random() * 3 + 1;
    this.speedY = -(Math.random() * 1 + 0.5);
    this.opacity = Math.random() * 0.6 + 0.2;
    this.drift = (Math.random() - 0.5) * 0.5;
  }
  // ... update/draw
}
```

- 下から上に金色の粒が緩やかに浮遊
- 5秒程度で消える
- パフォーマンス: 30個以下、requestAnimationFrame

---

## エピソードリスト画面の強化

### v3 変更点

| 要素 | v2 | v3 |
|------|----|----|
| エピソードカード | フラットなリスト | **映画ポスター風カード** |
| ヘッダー | テキストのみ | ロゴ + ビジュアル演出 |
| 再生ボタン | 小さいテキストボタン | **大きな再生ボタン + パルスエフェクト** |

### エピソードカード（v3）

```
┌─────────────────────────────────────────┐
│                                         │
│  EP.1                                   │  ← 大きな番号（text-4xl, 金色, 透かし）
│                                         │
│  初期化の風                              │  ← text-xl, 白
│  プロジェクト初期化。Astro + Cloudflare  │  ← text-sm, dim
│  Pages の構築に挑む                      │
│                                         │
│  3 scenes  ·  🌟🔵✈️🔫👮              │  ← 登場キャスト
│                                         │
│                              ▶ PLAY     │  ← 右下に再生ボタン
└─────────────────────────────────────────┘
```

- ホバーでカード全体が持ち上がる（`transform: translateY(-4px)` + shadow 増加）
- EP番号は背景に大きく透かし表示（watermark 風）
- 登場キャスト emoji をフッターに表示（脚本データから取得）

### 「撮影中」エピソード

v2: 🔒 テキストだけ
v3: カード全体にフィルムノイズ風のオーバーレイ + 赤い「REC」ドット点滅

```css
@keyframes rec-blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.3; }
}

.ep-recording::after {
  content: '● REC';
  color: #ef4444;
  font-size: 0.7rem;
  letter-spacing: .1em;
  animation: rec-blink 1.5s ease-in-out infinite;
}
```

---

## Auto Play モード（新機能）

### コンセプト

スクロールせずに自動で脚本が進行するモード。
「映画を観る」体験に最も近い。

### 動作

1. 再生ボタン横に「Auto ▶」トグルを配置
2. 有効にすると:
   - ナレーション → 文字数に応じた表示時間（50ms/文字 + 2秒）
   - セリフ → タイプライター表示 + 表示時間
   - シーン転換 → 自動ワイプ（2秒）
   - FIN → 自動演出
3. 画面下部に進捗バー（映画のシークバー風）
4. クリックで一時停止、再クリックで再開
5. 速度調整: 0.5x / 1x / 1.5x / 2x

### UI

```
┌─────────────────────────────────────────────┐
│                                             │
│  [脚本表示エリア]                            │
│                                             │
├─────────────────────────────────────────────┤
│ ◀◀  ❚❚  ▶▶  │████████░░░░│ 1:23 / 3:45  1x│  ← シークバー
└─────────────────────────────────────────────┘
```

### 実装の注意

- Auto Play は**オプション機能**。デフォルトはスクロールモード
- スクロールモードでもアニメーション演出は有効
- Auto Play 中にスクロールしたら Auto Play 解除

---

## 背景演出

### シーン別背景

脚本の `mood` フィールド（将来対応）で背景のトーンを変える:

| mood | 背景演出 |
|------|---------|
| `tense` | 背景が暗めに + 赤みのある vignette |
| `triumph` | 背景に金色のグラデーション追加 |
| `calm` | デフォルト（現在の暗い紫） |
| `comedy` | 背景がわずかに明るめ |
| `crisis` | 画面端が赤く脈動 |

v3 初期実装では `mood` 未対応。FINAL SCENE のみ金色背景を適用。

### 背景パーティクル（常時）

画面全体に非常に薄い金色の塵が漂うエフェクト:

```css
/* CSS のみで実装（パフォーマンス優先） */
@keyframes float-dust {
  0% { transform: translateY(100vh) rotate(0deg); opacity: 0; }
  10% { opacity: 0.3; }
  90% { opacity: 0.3; }
  100% { transform: translateY(-10vh) rotate(360deg); opacity: 0; }
}

.dust-particle {
  position: fixed;
  width: 2px;
  height: 2px;
  background: #f0c040;
  border-radius: 50%;
  opacity: 0;
  pointer-events: none;
  animation: float-dust var(--duration) linear infinite;
}
```

- 8-12個程度を CSS animation で配置（JS 不要）
- `pointer-events: none` でインタラクション妨害しない
- Owner の好みで OFF にできるトグル付き

---

## 画面構成（v3）

```
┌─ ENSEMBLE CAST — THEATER ───────────────────────────────────┐
│                                                              │
│  [金色の塵パーティクル（背景）]                               │
│                                                              │
│            ┌─ SCREEN ─────────────────────────┐             │
│            │                                   │             │
│            │      E P I S O D E  1             │             │
│            │                                   │             │
│            │      初 期 化 の 風               │   ← 巨大タイトル
│            │                                   │             │
│            │  ─────── ✦ ───────                │   ← 金色区切り
│            │                                   │             │
│            │  SCENE 1 — 作戦開始               │   ← text-2xl
│            │                                   │             │
│            │  新しいプロジェクトの幕が上がる。  │   ← ナレーション中央
│            │  チームは未知の技術スタックに      │     text-lg italic
│            │  挑もうとしていた。                │             │
│            │                                   │             │
│            │  ┃ 🔵 ブチャラティ                │   ← キャラカラーバー
│            │  ┃ タスクボードを見据えて          │     ト書き dim
│            │  ┃                                │             │
│            │  ┃ 「全員、持ち場につけ。          │   ← text-2xl セリフ
│            │  ┃  今回は時間との戦いだ」         │             │
│            │  ┃                                │             │
│            │                                   │             │
│            │  ┃ 🌟 ジョルノ                     │   ← 金色バー
│            │  ┃ 静かに立ち上がる                │             │
│            │  ┃                                │             │
│            │  ┃ 「トップページは                │   ← text-3xl 強調
│            │  ┃  僕が引き受けます。             │     (シーン最後=dramatic)
│            │  ┃  ...これが、僕の               │             │
│            │  ┃  『覚悟』です」                 │             │
│            │                                   │             │
│            │  ═══════ ✦ ═══════                │   ← シーンワイプ
│            │                                   │             │
│            │  ...                              │             │
│            │                                   │             │
│            │         ─── ✦ ───                 │             │
│            │                                   │             │
│            │          F  I  N                  │   ← text-6xl
│            │                                   │             │
│            │    Episode 1 — 初期化の風          │             │
│            │                                   │             │
│            │        [金色パーティクル]           │             │
│            │                                   │             │
│            └───────────────────────────────────┘             │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ ◀ EP.0 (locked) │ ████████████ 完 │ EP.2 ▶          │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  🍿 ENSEMBLE CAST Theater v3.0 · 📡 Control Room →         │
└──────────────────────────────────────────────────────────────┘
```

---

## CSS アニメーション一覧

| アニメーション | 対象 | 効果 | 時間 |
|---------------|------|------|------|
| `title-reveal` | エピソードタイトル | scale + letter-spacing 展開 | 1.5s |
| `subtitle-rise` | サブタイトル | 下からフェード + blur解除 | 1s |
| `scene-wipe` | シーン間区切り線 | 中央から左右に光が広がる | 1.5s |
| `char-entrance` | キャラ名（初登場時） | 左からスライド + グロー | 0.8s |
| `beat-slide` | セリフブロック | 左からスライドイン | 0.5s |
| `narration-reveal` | ナレーション | フェード + blur解除 | 1s |
| `direction-fade` | ト書き | フェードイン | 0.4s |
| `fin-grand` | FIN 文字 | scale + letter-spacing + グロー | 2s |
| `fin-line-expand` | FIN 前の金線 | 中央から展開 | 1s |
| `float-dust` | 背景パーティクル | 下から上に浮遊 | 15-25s |
| `rec-blink` | REC インジケータ | 点滅 | 1.5s |
| `card-hover` | エピソードカード | 持ち上がり + shadow | 0.3s |
| `dramatic-glow` | 強調セリフ | text-shadow パルス | 2s |

---

## 脚本 YAML 拡張（後方互換）

Theater v3 の演出を最大限活かすため、脚本 YAML にオプションフィールドを追加。
**すべてオプション。v2 脚本もそのまま表示可能。**

```yaml
# episodes/ep1.yaml（v3 拡張フィールド）
scenes:
  - scene: 3
    title: "最初の光"
    mood: "triumph"           # ← 新: 背景演出に使用
    narration: "..."
    beats:
      - character: "giorno"
        action: "モニターに映る画面を見て微笑む"
        dialogue: "見えますか、ブチャラティ。これが僕たちの最初の一歩です"
        dramatic: true          # ← 新: 強調セリフ
      - character: "narancia"
        action: "画面を指さして"
        dialogue: "おお！動いてるぜ！マジで動いてる！"
        emphasis: "excited"     # ← 新: セリフのトーン（将来拡張）
```

### 脚本生成プロンプトへの追記

`scripts/screenplay-prompt.md` に v3 演出フィールドの説明を追記:
- `dramatic: true` → シーンのクライマックスセリフに付与
- `mood` → シーンの雰囲気（tense / triumph / calm / comedy / crisis）
- 既存フィールドには影響しない

---

## API 変更

### GET /api/episodes/{n} レスポンス拡張

```json
{
  "episode": 1,
  "title": "初期化の風",
  "synopsis": "...",
  "cast_appearing": ["giorno", "bucciarati", "narancia", "mista", "abbacchio"],
  "scenes": [
    {
      "scene": 1,
      "title": "作戦開始",
      "mood": "calm",
      "narration": "...",
      "beats": [
        {
          "character": "bucciarati",
          "action": "タスクボードを見据えて",
          "dialogue": "全員、持ち場につけ。今回は時間との戦いだ",
          "dramatic": false
        }
      ]
    }
  ]
}
```

新フィールド:
- `cast_appearing` — エピソードリストで登場キャスト emoji 表示に使用
- `mood` — シーン背景演出
- `dramatic` — セリフ強調

すべてオプション。存在しなければデフォルト値（calm / false）。

---

## パフォーマンス設計

### 原則: CSS First

| レイヤー | 技術 | 用途 |
|---------|------|------|
| 1（最優先） | CSS animation / transition | テキストアニメーション、グロー、スライド |
| 2 | CSS + HTML要素 | 背景パーティクル（`<div>` × 12個） |
| 3（最小限） | Canvas | FIN パーティクル（5秒間のみ） |
| 4（将来） | JS animation | Auto Play タイプライター |

- `will-change` は使用箇所を限定（常時 transform するものだけ）
- `@media (prefers-reduced-motion)` で演出を控えめにするフォールバック
- Canvas は FIN 時のみ生成、終了後に destroy

### 単一 HTML ファイル方針は維持

```
ui/theater.html  ← この1ファイルを改修（npm/ビルド不要）
```

Google Fonts の追加フォント読み込みなし（Noto Sans JP のまま）。
ウェイト 300/400/500/700 で十分な表現力がある。

---

## 設定トグル

Theater 画面右上にギアアイコンで設定パネル:

| 設定 | デフォルト | 説明 |
|------|-----------|------|
| 背景パーティクル | ON | 金色の塵エフェクト |
| アニメーション強度 | 標準 | 控えめ / 標準 / 派手 |
| Auto Play | OFF | 自動再生モード |
| Auto Play 速度 | 1x | 0.5x / 1x / 1.5x / 2x |

設定は `localStorage` に保存。

---

## 実装計画

### Phase 1: タイポグラフィ + キャラ演出（最優先）

最も効果が高い。文字の大きさとキャラカラーバーだけで体験が劇的に変わる。

1. フォントサイズ階層の適用
2. キャラカラーバー（border-left）
3. セリフ本文の大型化
4. ナレーションの中央寄せ + 装飾線

### Phase 2: トランジション + FIN

1. Opening 演出（タイトル展開アニメーション）
2. シーンワイプ（金色ラインの展開）
3. FIN グランド演出
4. FIN パーティクル（Canvas）

### Phase 3: エピソードリスト + 背景

1. エピソードカードの映画ポスター風デザイン
2. REC インジケータ
3. 背景パーティクル（CSS）
4. 設定トグルパネル

### Phase 4: Auto Play + 拡張フィールド

1. Auto Play モードの実装
2. シークバー UI
3. `dramatic` / `mood` フィールド対応
4. 脚本生成プロンプト更新

---

## v2 → v3 マイグレーション

### 後方互換性

- v2 脚本（`dramatic` / `mood` なし）はそのまま表示可能
- 新フィールドがない場合はデフォルト演出を適用
- API の既存フィールドは削除しない

### theater-server.py の変更

- `/api/episodes/{n}` に `cast_appearing` フィールド追加
  - 脚本の全 beats から character を収集して deduplicate
- 新フィールド（`mood`, `dramatic`）はそのまま pass-through
