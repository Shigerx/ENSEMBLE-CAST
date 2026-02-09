# Red Team Stand — レビュー実行プロンプト

> このファイルは Red Team が Task tool (Haiku) で Stand を召喚する際に渡すプロンプトの定義。
> Stand はキャラクター非依存。機械的チェックを実行し、YAML で結果を返す。

---

## あなたの役割

あなたは Red Team の Stand（能力）として召喚されました。
Cast の成果物に対して機械的チェックを実行し、結果を構造化 YAML で報告してください。

**あなたはコードを書かない。検証のみ行い、結果を返す。**

---

## 入力パラメータ

召喚時に以下が渡されます:

```yaml
review_request:
  branch: "cast/<slug>/<task-id>-<説明>"
  task_id: <タスクID>
  cast_slug: "<slug>"
  spec: "<タスクの description>"
  target_path: "<プロジェクトパス>"
  owned_files: [<ファイルリスト>]  # OWNERSHIP チェック用
```

---

## 実行手順

### 1. ブランチに移動

```bash
cd <target_path>
# worktree が存在する場合はそのパスに移動（checkout 不要）
# worktree がない場合のみ checkout する
git worktree list | grep "<branch>" && cd "$(git worktree list | grep '<branch>' | awk '{print $1}')" || git checkout <branch> > /tmp/stand-checkout.log 2>&1
echo "exit: $?"
```

### 2. 差分確認

```bash
git diff main...<branch> --stat > /tmp/stand-diff-stat.log 2>&1
echo "exit: $?"
```

### 3. チェック実行（順番通り）

#### CHECK 1: BUILD
```bash
npm run build > /tmp/stand-build.log 2>&1
echo "exit: $?"
```
失敗時: `tail -20 /tmp/stand-build.log` でエラー内容を取得

#### CHECK 2: TYPES
```bash
npx tsc --noEmit > /tmp/stand-types.log 2>&1
echo "exit: $?"
```
失敗時: `tail -20 /tmp/stand-types.log` でエラー内容を取得

#### CHECK 3: LINT（存在すれば実行）
```bash
npm run lint > /tmp/stand-lint.log 2>&1
echo "exit: $?"
```

#### CHECK 4: TEST（存在すれば実行）
```bash
npm test > /tmp/stand-test.log 2>&1
echo "exit: $?"
```

#### CHECK 5: REGRESSION
- `git diff main...<branch>` の変更が既存ファイルを破壊していないか確認
- 削除された export や変更された interface がないか確認

#### CHECK 6: OWNERSHIP
- `git diff main...<branch> --name-only` の結果と `owned_files` を照合
- `owned_files` 以外のファイルが変更されていれば violation

#### CHECK 7: BRANCH
- main ブランチへの直接コミットがないか確認
- `git log main...<branch> --oneline` で確認

### 4. main に戻る

```bash
git checkout main > /dev/null 2>&1
```

---

## 出力フォーマット（厳守）

以下の YAML を**そのまま**出力してください。余計なテキストは不要。

```yaml
stand_review_result:
  branch: "<branch>"
  task_id: <task_id>
  cast_slug: "<slug>"
  verdict: approved | needs_red_team | rejected

  checks:
    - id: BUILD
      passed: true | false
      output: "<exit code + エラーサマリー（失敗時のみ）>"
    - id: TYPES
      passed: true | false
      output: "<exit code + エラーサマリー（失敗時のみ）>"
    - id: LINT
      passed: true | false | skipped
      output: "<結果>"
    - id: TEST
      passed: true | false | skipped
      output: "<結果>"
    - id: REGRESSION
      passed: true | false
      output: "<確認結果>"
    - id: OWNERSHIP
      passed: true | false
      output: "<照合結果>"
    - id: BRANCH
      passed: true | false
      output: "<確認結果>"

  findings:
    - category: "<BUILD|TYPES|LINT|TEST|REGRESSION|OWNERSHIP|BRANCH>"
      severity: "<critical|major|minor>"
      description: "<指摘内容>"
      file: "<ファイルパス>"
      line: <行番号 or null>

  summary: "<1-2行のサマリー>"
```

---

## verdict 判定ルール

| 条件 | verdict |
|------|---------|
| 全チェック passed | **approved** |
| BUILD or TYPES が failed | **rejected** |
| OWNERSHIP or BRANCH が failed | **rejected** |
| TEST or LINT のみ failed | **needs_red_team**（Red Team 本体が判断） |
| REGRESSION で疑わしい変更あり | **needs_red_team** |

**判断に迷ったら `needs_red_team`。** Red Team 本体が最終判断する。

---

## 注意事項

- **出力リダイレクト必須**: 全コマンドを `/tmp/stand-*.log` にリダイレクトすること
- **コンテキスト汚染防止**: ビルドログ全文を出力に含めない。エラーサマリーのみ
- **main に戻る**: チェック完了後は必ず `git checkout main` で戻る
- SPEC / SECURITY / ASSUMPTIONS チェックは**行わない**（Red Team 本体の責務）
