# nepolabo-todo — プロジェクトコンテキスト

## What
Phase 2: 期限管理とカテゴリ機能の追加。ねぽらぼっぽいエッセンスを取り入れたTODOアプリ。

## Why
- 既存の基本機能（CRUD、フィルタ）に期限・カテゴリを追加して実用性を高める
- ホロライブ5期生（ねぽらぼ）のテーマで開発する練習プロジェクト

## Who
| 担当 | 役割 | 責務 |
|------|------|------|
| ぼたん | アーキテクト/リード | 期限管理UI（DatePicker、表示、警告） |
| ねね | フロントエンド担当 | カテゴリ機能UI（選択・作成・フィルタ） |
| ポルカ | UI/UXデザイン担当 | App統合、ねぽらぼスタイリング |
| ラミィ | Reviewer | 品質検証、ビルド・テスト実行 |

## Constraints
- 技術スタック: React, TypeScript, Vite, Tailwind CSS
- 対象パス: /mnt/c/Users/shige/antigravity/nepolabo-todo
- 既存の型定義（dueDate, category）を活用する
- レース条件防止: 各キャストは専用ファイルで作業

## Current State
- フェーズ: キャスティング完了、タスク配布待ち
- 進捗: 0%
- 次のアクション: 着任報告確認後、初期タスク配布
- ブロッカー: なし

## Decisions
| 日付 | 決定事項 | 理由 |
|------|---------|------|
| 2026-01-29 | 既存型定義を活用 | dueDate, categoryフィールドが既に存在 |
| 2026-01-29 | ラミィをReviewer役に | 品質検証専任で品質向上 |

## Notes
- useTodos.ts に addTodo(title, category?, dueDate?) が既に存在
- App.tsx はプレースホルダー状態（実装待ち）
- components/ に AddTodoForm, TodoItem, TodoList が存在（要統合）
