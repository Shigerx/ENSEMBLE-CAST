# Theater v4 設計書: シネマティック・パララックス演出エンジン

## 実装済み機能

### Phase 1: 映画館フレーム
- **body真っ黒**: `background:#000` で暗闇演出
- **theater-frame**: max-width:1100px の中央配置コンテナ
- **レターボックス**: 上下8vh（モバイル4vh）の固定黒帯
- **screen-surface**: mood連動グロー（CSS custom property `--glow-color`）
- **フィルムグレイン**: SVG feTurbulence base64化、opacity:0.035、4フレーム巡回
- **赤カーテン開幕**: radial-gradientで布地テクスチャ、2s transition
- 設定: `filmGrain`, `curtainOpen` トグル

### Phase 2: キャラ左右配置
- SceneBlock内 `charPositions` Map で最初→LEFT、次→RIGHT
- `beat-block-left` / `beat-block-right` CSS
- 設定: `dialogueStyle` = `classic`（v3互換）/ `cinematic`（v4）

### Phase 3: mood駆動エントリーアニメーション
- calm: フェード+微スライド (0.6s)
- tense: scale(1.3)→1 カットイン (0.2s)
- triumph: translateY(40px)→0 せり上がり (0.8s)
- comedy: scale(0.5)→1.05→1 bounce + 吹き出しフレーム
- crisis: translateX(-50px)→0 + screen-shake (0.15s)
- タイポグラフィ自動判定: `！`→1.75rem、`...`→1.25rem、crisis/tense→1段階UP
- 設定: `dramaticEffects` トグル

### Phase 4: シーン転換システム
- simple: v3金色ワイプ（後方互換）
- iris: clip-path circle() アイリスアウト/イン + リングインジケータ
- fade: フェード・トゥ・ブラック
- mood別自動選択はtransitionStyle設定に基づく
- 設定: `transitionStyle` = `simple` / `iris` / `fade`

### Phase 5: ドラマティックモーメント
- dramatic-takeover: 暗幕 + 2.5rem + text-shadow グロー
- scroll-snap-type: y proximity
- dramatic-scale-in: scale(1.1)→1 + blur(2px)→0
- golden-pulse: 最終ビート金色脈動
- 設定: `dramaticEffects` トグル

### Phase 6: パララックス3層
- foreground (z:3, opacity:1.0): セリフ
- midground (z:2, opacity:0.85): ナレーション
- background (z:1, opacity:0.45): ト書き(action) + subtle-drift
- parallax-subtle / parallax-normal で深度制御
- Auto Play中はパララックス無効
- 設定: `parallaxDepth` = `off` / `subtle` / `normal`

### Phase 7: 統合
- カーテン開幕 → エピソード読み込み後0.8sでトリガー
- Auto Play中パララックス無効
- prefers-reduced-motion 全対応
- フッター v4.0

## 設定パネル

| 設定 | 型 | デフォルト |
|------|---|---------|
| filmGrain | toggle | ON |
| curtainOpen | toggle | ON |
| parallaxDepth | select | normal |
| dialogueStyle | select | cinematic |
| transitionStyle | select | iris |
| dramaticEffects | toggle | ON |

## YAML拡張: なし
全て既存フィールド（mood/dramatic/action/character）から導出。後方互換維持。

## prefers-reduced-motion
全新規アニメーション無効化。カーテン非表示。パララックス無効。
