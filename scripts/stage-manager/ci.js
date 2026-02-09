/**
 * Stage Manager - ci.js
 * Git post-commit hook から呼ばれる CI 自動テスト実行エンジン
 *
 * 直近のコミットのブランチ名を取得し、config/ci.yaml に従い
 * 段階的テスト（level 1〜4）を実行する。
 * 結果を queue/ci_results/<branch-slug>.yaml に出力し、
 * 全ログを logs/ci/<branch-slug>.log に出力する。
 * 通知は行わない（notify-ci.sh に委譲）。
 *
 * 外部依存なし（Node.js 標準ライブラリのみ）。
 */
'use strict';

const { execSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

// =============================================================================
// レベルごとのコマンド順序定義
// =============================================================================

/**
 * テストレベルとコマンド名の対応
 * level 1: build のみ
 * level 2: build + typecheck
 * level 3: build + typecheck + test
 * level 4: build + typecheck + test + e2e
 */
const LEVEL_COMMANDS = ['build', 'typecheck', 'test', 'e2e'];

// =============================================================================
// ブランチ名 → スラッグ変換
// =============================================================================

/**
 * ブランチ名のスラッシュをハイフンに変換してスラッグ化する
 * @param {string} branch
 * @returns {string}
 */
function branchToSlug(branch) {
  return branch.replace(/\//g, '-');
}

// =============================================================================
// ci.yaml パーサー
// =============================================================================

/**
 * ci.yaml をパースして設定オブジェクトを返す
 *
 * 対応フォーマット:
 *   level: 2
 *   commands:
 *     build: "npm run build"
 *     typecheck: "npx tsc --noEmit"
 *     test: "npm test"
 *     e2e: "npx playwright test"
 *
 * @param {string|null} yamlStr
 * @returns {{ level: number, commands: Record<string, string> }}
 */
function parseCiConfig(yamlStr) {
  const defaults = { level: 1, commands: {} };

  if (!yamlStr || typeof yamlStr !== 'string' || yamlStr.trim() === '') {
    return defaults;
  }

  const lines = yamlStr.split('\n');
  let level = 1;
  const commands = {};
  let inCommands = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // コメント行・空行をスキップ
    if (/^\s*#/.test(line) || /^\s*$/.test(line)) continue;

    // level: N
    const levelMatch = line.match(/^level:\s*"?(\d+)"?\s*$/);
    if (levelMatch) {
      level = parseInt(levelMatch[1], 10);
      inCommands = false;
      continue;
    }

    // commands: （セクション開始）
    if (/^commands:\s*$/.test(line)) {
      inCommands = true;
      continue;
    }

    // トップレベルの別キー → commands セクション終了
    if (/^\S/.test(line) && !line.startsWith('commands:')) {
      inCommands = false;
      continue;
    }

    // commands 内のエントリ: "  build: ..."
    if (inCommands) {
      const cmdMatch = line.match(/^\s+(\w+):\s*"?([^"]*)"?\s*$/);
      if (cmdMatch) {
        commands[cmdMatch[1]] = cmdMatch[2].trim();
      }
    }
  }

  return { level, commands };
}

// =============================================================================
// レベルに応じたコマンドリスト取得
// =============================================================================

/**
 * テストレベルに応じて実行すべきコマンドのリストを返す
 * コマンドが commands に存在しない場合はスキップする
 *
 * @param {number} level - テストレベル（1〜4）
 * @param {Record<string, string>} commands - コマンド定義
 * @returns {Array<{ name: string, command: string }>}
 */
function getCommandsForLevel(level, commands) {
  if (level <= 0) return [];

  const effectiveLevel = Math.min(level, LEVEL_COMMANDS.length);
  const result = [];

  for (let i = 0; i < effectiveLevel; i++) {
    const name = LEVEL_COMMANDS[i];
    if (commands[name]) {
      result.push({ name, command: commands[name] });
    }
  }

  return result;
}

// =============================================================================
// 結果YAML文字列の生成
// =============================================================================

/**
 * CI 結果を YAML 文字列にフォーマットする
 *
 * @param {object} data
 * @param {string} data.branch
 * @param {string} data.commit
 * @param {string} data.timestamp
 * @param {number} data.level
 * @param {Record<string, { status: string, duration_ms: number, summary?: string }>} data.results
 * @param {string} data.overall
 * @param {string} data.log_path
 * @returns {string}
 */
function formatResults(data) {
  let yaml = '';

  yaml += `branch: "${data.branch}"\n`;
  yaml += `commit: "${data.commit}"\n`;
  yaml += `timestamp: "${data.timestamp}"\n`;
  yaml += `level: ${data.level}\n`;

  yaml += `results:\n`;
  for (const [name, result] of Object.entries(data.results)) {
    yaml += `  ${name}:\n`;
    yaml += `    status: "${result.status}"\n`;
    yaml += `    duration_ms: ${result.duration_ms}\n`;
    if (result.summary) {
      yaml += `    summary: "${result.summary}"\n`;
    }
  }

  yaml += `overall: "${data.overall}"\n`;
  yaml += `log_path: "${data.log_path}"\n`;

  return yaml;
}

// =============================================================================
// production.yaml パーサー（target_path 取得）
// =============================================================================

/**
 * production.yaml から target_path を取得する
 *
 * @param {string|null} yamlStr
 * @returns {string|null}
 */
function parseProductionYaml(yamlStr) {
  if (!yamlStr || typeof yamlStr !== 'string' || yamlStr.trim() === '') {
    return null;
  }

  // target_path: null or target_path: ~ → null
  const nullMatch = yamlStr.match(/^\s+target_path:\s*(null|~)\s*$/m);
  if (nullMatch) {
    return null;
  }

  // target_path: "value" or target_path: value
  const match = yamlStr.match(/^\s+target_path:\s*"?([^"\n]+)"?\s*$/m);
  if (match) {
    const val = match[1].trim();
    if (val === 'null' || val === '~') return null;
    return val;
  }

  return null;
}

// =============================================================================
// コマンド実行
// =============================================================================

/**
 * 単一のテストコマンドを実行し、結果を返す
 *
 * @param {string} name - コマンド名（build, typecheck, test, e2e）
 * @param {string} command - 実行コマンド
 * @param {string} cwd - 実行ディレクトリ
 * @param {number} fd - ログファイルの fd
 * @returns {{ status: string, duration_ms: number, summary?: string }}
 */
function runCommand(name, command, cwd, fd) {
  const header = `\n${'='.repeat(60)}\n[CI] ${name}: ${command}\n${'='.repeat(60)}\n`;
  fs.writeSync(fd, header);

  const startTime = Date.now();
  try {
    const output = execSync(command, {
      cwd,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: 300000, // 5分タイムアウト
    });
    const duration = Date.now() - startTime;

    fs.writeSync(fd, output || '(no output)\n');
    fs.writeSync(fd, `\n[CI] ${name}: PASS (${duration}ms)\n`);

    return { status: 'pass', duration_ms: duration };
  } catch (e) {
    const duration = Date.now() - startTime;

    // stdout と stderr を結合してログに出力
    const output = (e.stdout || '') + (e.stderr || '');
    fs.writeSync(fd, output || '(no output)\n');
    fs.writeSync(fd, `\n[CI] ${name}: FAIL (${duration}ms, exit code: ${e.status})\n`);

    // エラーサマリーを生成（stderr の最後の行、または stdout の最後の行）
    const lines = (e.stderr || e.stdout || '').trim().split('\n').filter(Boolean);
    const summary = lines.length > 0
      ? lines[lines.length - 1].substring(0, 200)
      : `exit code ${e.status}`;

    return { status: 'fail', duration_ms: duration, summary };
  }
}

// =============================================================================
// メインロジック（post-commit hook として実行時）
// =============================================================================

/**
 * post-commit hook メイン処理
 */
function main() {
  try {
    // ENSEMBLE-CAST ルートを特定
    const repoRoot = execSync('git rev-parse --show-toplevel', { encoding: 'utf-8' }).trim();

    // 1. 現在のブランチ名を取得
    let branchName;
    try {
      branchName = execSync('git symbolic-ref --short HEAD', { encoding: 'utf-8' }).trim();
    } catch {
      // detached HEAD（rebase 中等）→ スキップ
      process.stderr.write('[CI] detached HEAD 状態のためスキップします\n');
      process.exit(0);
    }

    // 2. 直近のコミットハッシュを取得
    const commitHash = execSync('git rev-parse --short HEAD', { encoding: 'utf-8' }).trim();

    // 3. config/ci.yaml を読み込む
    const ciConfigPath = path.join(repoRoot, 'config', 'ci.yaml');
    let ciConfig;
    try {
      const ciConfigContent = fs.readFileSync(ciConfigPath, 'utf-8');
      ciConfig = parseCiConfig(ciConfigContent);
    } catch {
      // ci.yaml が読めない → デフォルト level 1
      process.stderr.write('[CI] config/ci.yaml が読めません。デフォルト level 1 で実行します\n');
      ciConfig = { level: 1, commands: {} };
    }

    // 4. production.yaml から target_path を取得
    const productionPath = path.join(repoRoot, 'config', 'production.yaml');
    let targetPath = null;
    try {
      const productionContent = fs.readFileSync(productionPath, 'utf-8');
      targetPath = parseProductionYaml(productionContent);
    } catch {
      // production.yaml が読めない → リポジトリルートを使用
    }

    // テストコマンドの実行ディレクトリ
    const execCwd = targetPath || repoRoot;

    // 5. 実行コマンドリストを取得
    const commandList = getCommandsForLevel(ciConfig.level, ciConfig.commands);

    if (commandList.length === 0) {
      process.stderr.write('[CI] 実行可能なコマンドがありません。スキップします\n');
      process.exit(0);
    }

    // 6. 出力ディレクトリを作成
    const slug = branchToSlug(branchName);
    const ciResultsDir = path.join(repoRoot, 'queue', 'ci_results');
    const ciLogsDir = path.join(repoRoot, 'logs', 'ci');

    fs.mkdirSync(ciResultsDir, { recursive: true });
    fs.mkdirSync(ciLogsDir, { recursive: true });

    // 7. ログファイルを開く
    const logPath = path.join(ciLogsDir, `${slug}.log`);
    const logFd = fs.openSync(logPath, 'w');

    const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, '');

    fs.writeSync(logFd, `[CI] Branch: ${branchName}\n`);
    fs.writeSync(logFd, `[CI] Commit: ${commitHash}\n`);
    fs.writeSync(logFd, `[CI] Level: ${ciConfig.level}\n`);
    fs.writeSync(logFd, `[CI] Timestamp: ${timestamp}\n`);
    fs.writeSync(logFd, `[CI] CWD: ${execCwd}\n`);

    // 8. コマンドを順次実行
    const results = {};
    let overall = 'pass';
    let stopOnFail = false;

    for (const { name, command } of commandList) {
      if (stopOnFail) {
        // 前のステップが失敗した場合、後続はスキップ
        results[name] = { status: 'skip', duration_ms: 0, summary: 'skipped due to previous failure' };
        continue;
      }

      const result = runCommand(name, command, execCwd, logFd);
      results[name] = result;

      if (result.status === 'fail') {
        overall = 'fail';
        stopOnFail = true;
      }
    }

    fs.closeSync(logFd);

    // 9. 結果 YAML を出力
    const relativeLogPath = `logs/ci/${slug}.log`;
    const resultData = {
      branch: branchName,
      commit: commitHash,
      timestamp,
      level: ciConfig.level,
      results,
      overall,
      log_path: relativeLogPath,
    };

    const resultYaml = formatResults(resultData);
    const resultPath = path.join(ciResultsDir, `${slug}.yaml`);
    fs.writeFileSync(resultPath, resultYaml, 'utf-8');

    process.stderr.write(`[CI] ${overall === 'pass' ? 'PASS' : 'FAIL'} — ${resultPath}\n`);

    // ci.js 自体は常に exit 0 で終了する（hookの中断を避ける）
    process.exit(0);
  } catch (e) {
    process.stderr.write(`[CI] 予期しないエラー: ${e.message}\n`);
    // ci.js 自体は常に exit 0 で終了する（hookの中断を避ける）
    process.exit(0);
  }
}

// =============================================================================
// エクスポート（テスト用）+ メイン実行
// =============================================================================

module.exports = {
  branchToSlug,
  parseCiConfig,
  getCommandsForLevel,
  formatResults,
  parseProductionYaml,
  runCommand,
};

// 直接実行時のみ main() を呼ぶ
if (require.main === module) {
  main();
}
