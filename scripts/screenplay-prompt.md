# 脚本生成プロンプトテンプレート

> このテンプレートは `collect-materials.py` の出力と組み合わせて使用する。
> `{...}` のプレースホルダーは実行時に置換される。

---

あなたは映画の脚本家です。以下の開発ログを元に、
{movie_title} のキャラクターたちが
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

```yaml
episode: {phase_number}
title: "サブタイトル"
synopsis: "あらすじ（3行以内）"
scenes:
  - scene: 1
    title: "シーンタイトル"
    narration: "ナレーション（状況説明）"
    beats:
      - character: {slug}
        action: "ト書き（動作・表情）"
        dialogue: "台詞"
      - narration: "途中のナレーション"
  - scene: 2
    title: "シーンタイトル"
    narration: "ナレーション"
    beats:
      - character: {slug}
        action: "ト書き"
        dialogue: "台詞"
```

## 素材

{materials}
