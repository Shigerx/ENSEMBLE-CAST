# Team Knowledge — チーム知識ベース

Phase 完了時に `scripts/distill-phase.sh` で蒸留された知見を蓄積するディレクトリ。
新しい Cast がプロジェクト開始時に読み込み、過去の教訓を活用する。

## ファイル構成

| ファイル | 内容 |
|---------|------|
| patterns.yaml | うまくいったパターン（再現推奨） |
| anti_patterns.yaml | 失敗パターン（再発防止） |
| decisions.yaml | 重要な技術判断の記録 |
| retrospective.yaml | Phase 振り返り |

## 更新タイミング

- Phase 完了時: Director が `scripts/distill-phase.sh` を実行
- 蒸留は Task tool（Haiku モデル推奨）で定型処理として実行
- 手動追記も可（Director が重要な知見を即座に記録する場合）

## 読み込みタイミング

- Cast 起動時のコンテキスト読み込み手順で参照（任意だが推奨）
- コンパクション復帰時は省略可（chronicle.yaml の handoff を優先）
