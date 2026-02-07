/**
 * Stage Manager - checkpoint.js
 * 各 Agent の状態をスナップショットとして保存する。
 *
 * コンパクション復帰が 10ステップ → 2ステップに:
 *   1. checkpoints/<slug>.yaml を読む
 *   2. 作業再開
 *
 * 外部依存なし（Node.js 標準ライブラリのみ）。
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execSync } = require('node:child_process');

// =============================================================================
// panes.yaml パーサー
// =============================================================================

/**
 * panes.yaml をパースする。
 * 形式:
 *   producer: "%0"
 *   director: "%1"
 *   cast:
 *     botan: "%2"
 *     nene: "%3"
 *
 * @param {string} yamlStr
 * @returns {{ producer: string, director: string, cast: Object<string, string> }}
 */
function parsePanesYaml(yamlStr) {
  const result = { producer: '', director: '', cast: {} };
  const lines = yamlStr.split('\n');
  let inCast = false;

  for (const line of lines) {
    // コメント行・空行をスキップ
    if (/^\s*#/.test(line) || /^\s*$/.test(line)) continue;

    // producer: "%0"
    const producerMatch = line.match(/^producer:\s*"([^"]+)"/);
    if (producerMatch) {
      result.producer = producerMatch[1];
      inCast = false;
      continue;
    }

    // director: "%1"
    const directorMatch = line.match(/^director:\s*"([^"]+)"/);
    if (directorMatch) {
      result.director = directorMatch[1];
      inCast = false;
      continue;
    }

    // cast: セクション開始
    if (/^cast:\s*$/.test(line)) {
      inCast = true;
      continue;
    }

    // cast 内のエントリ: "  slug: "%N""
    if (inCast) {
      const castEntry = line.match(/^\s+(\w+):\s*"([^"]+)"/);
      if (castEntry) {
        result.cast[castEntry[1]] = castEntry[2];
        continue;
      }
      // cast セクション終了（インデントなしの行が来たら）
      if (/^\S/.test(line)) {
        inCast = false;
      }
    }
  }

  return result;
}

// =============================================================================
// roster.yaml パーサー
// =============================================================================

/**
 * roster.yaml の members をパースする。
 *
 * @param {string} yamlStr
 * @returns {Array<{slug: string, dev_role: string, is_reviewer?: boolean, [key: string]: any}>}
 */
function parseRosterYaml(yamlStr) {
  const members = [];
  const lines = yamlStr.split('\n');
  let inMembers = false;
  let currentItem = null;

  for (const line of lines) {
    // コメント行・空行をスキップ
    if (/^\s*#/.test(line) || /^\s*$/.test(line)) continue;

    // members: [] → 空配列、パースしない
    if (/^members:\s*\[\]/.test(line)) {
      continue;
    }

    // members: セクション開始
    if (/^members:\s*$/.test(line)) {
      inMembers = true;
      continue;
    }

    // トップレベルの別キー → members セクション終了
    if (inMembers && /^\S/.test(line) && !line.startsWith(' ')) {
      inMembers = false;
      continue;
    }

    if (!inMembers) continue;

    // 配列アイテム開始: "  - slug: "botan""
    const arrayItemMatch = line.match(/^\s+-\s+(\w[\w_]*):\s*(.*)/);
    if (arrayItemMatch) {
      currentItem = {};
      currentItem[arrayItemMatch[1]] = parseYamlValue(arrayItemMatch[2].trim());
      members.push(currentItem);
      continue;
    }

    // 配列アイテムのプロパティ: "    key: value"
    const propMatch = line.match(/^\s{4,}(\w[\w_]*):\s*(.*)/);
    if (propMatch && currentItem !== null) {
      currentItem[propMatch[1]] = parseYamlValue(propMatch[2].trim());
      continue;
    }
  }

  return members;
}

// =============================================================================
// タスクファイルパーサー
// =============================================================================

/**
 * タスク YAML から最初のタスクの id, title, status を抽出する。
 *
 * @param {string} yamlStr
 * @returns {{ id: string, title: string, status: string } | null}
 */
function parseTaskYaml(yamlStr) {
  if (!yamlStr || !yamlStr.trim()) return null;

  const lines = yamlStr.split('\n');
  let inTasks = false;
  let firstTask = null;
  let inMultilineBlock = false;
  let multilineBaseIndent = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (/^\s*#/.test(line)) continue;

    // 複数行ブロック（description: | 等）のスキップ
    if (inMultilineBlock) {
      // 空行はブロック内として扱う
      if (/^\s*$/.test(line)) continue;
      // ブロックのインデント以上の行はブロック内
      const currentIndent = line.match(/^(\s*)/)[1].length;
      if (currentIndent >= multilineBaseIndent) continue;
      // インデントが戻ったらブロック終了
      inMultilineBlock = false;
    }

    if (/^\s*$/.test(line)) continue;

    // tasks: [] → 空タスク
    if (/^tasks:\s*\[\]/.test(line)) return null;

    // tasks: セクション開始
    if (/^tasks:\s*$/.test(line)) {
      inTasks = true;
      continue;
    }

    if (!inTasks) continue;

    // 最初のタスクアイテム開始: "  - id: 5"
    const arrayItemMatch = line.match(/^\s+-\s+(\w[\w_]*):\s*(.*)/);
    if (arrayItemMatch && !firstTask) {
      firstTask = {};
      const val = arrayItemMatch[2].trim();
      // 複数行ブロック開始チェック
      if (val === '|' || val === '>') {
        inMultilineBlock = true;
        // 配列アイテム行 "  - key: |" のインデント(2) + "- "(2) + "key: "(N) ≈ +6
        // 前提: tasks配列のインデントは2スペース
        multilineBaseIndent = line.match(/^(\s*)/)[1].length + 6;
      } else {
        firstTask[arrayItemMatch[1]] = String(parseYamlValue(val));
      }
      continue;
    }

    // 2つ目のタスクアイテム → 終了
    if (arrayItemMatch && firstTask) {
      break;
    }

    // 最初のタスクのプロパティ（4スペース以上のインデント）
    const propMatch = line.match(/^\s{4}(\w[\w_]*):\s*(.*)/);
    if (propMatch && firstTask) {
      const key = propMatch[1];
      const val = propMatch[2].trim();
      // 複数行ブロック開始チェック（description: | 等）
      if (val === '|' || val === '>') {
        inMultilineBlock = true;
        // プロパティ行 "    key: |" のインデント + 2 = ブロック本体のインデント
        multilineBaseIndent = line.match(/^(\s*)/)[1].length + 2;
        continue;
      }
      // id, title, status のみ収集
      if (key === 'id' || key === 'title' || key === 'status') {
        firstTask[key] = String(parseYamlValue(val));
      }
      continue;
    }
  }

  if (!firstTask || !firstTask.id) return null;

  return {
    id: firstTask.id,
    title: firstTask.title || '',
    status: firstTask.status || 'unknown',
  };
}

// =============================================================================
// YAML 値パーサー（guard.js の parseValue と同等）
// =============================================================================

/**
 * @param {string} val
 * @returns {string|number|boolean|null}
 */
function parseYamlValue(val) {
  if (val === 'null' || val === '~') return null;
  if (val === 'true') return true;
  if (val === 'false') return false;
  if (/^-?\d+$/.test(val)) return parseInt(val, 10);
  if (/^-?\d+\.\d+$/.test(val)) return parseFloat(val);
  if ((val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))) {
    return val.slice(1, -1);
  }
  if (val === '[]') return [];
  return val;
}

// =============================================================================
// Role 解決
// =============================================================================

/**
 * slug から role を解決する。
 *
 * @param {string} slug
 * @param {{ producer: string, director: string, cast: Object }} panes
 * @param {Array<{slug: string, is_reviewer?: boolean}>} roster
 * @returns {'producer'|'director'|'cast'|'reviewer'|null}
 */
function resolveRole(slug, panes, roster) {
  if (slug === 'producer') return 'producer';
  if (slug === 'director') return 'director';

  // cast メンバーから検索
  if (panes.cast && panes.cast[slug]) {
    const member = roster.find((m) => m.slug === slug);
    if (member && member.is_reviewer === true) {
      return 'reviewer';
    }
    return 'cast';
  }

  return null;
}

// =============================================================================
// コンテキストファイル収集
// =============================================================================

/**
 * role に応じたコンテキストファイルのリストを返す。
 *
 * @param {'producer'|'director'|'cast'|'reviewer'} role
 * @param {string} slug
 * @returns {string[]}
 */
function collectContextFiles(role, slug) {
  switch (role) {
    case 'producer':
      return [
        'queue/producer_to_director.yaml',
        'dashboard.md',
      ];
    case 'director':
      return [
        'queue/producer_to_director.yaml',
        'dashboard.md',
        'queue/pending_tasks.yaml',
      ];
    case 'cast':
    case 'reviewer':
      return [
        `queue/tasks/${slug}.yaml`,
        `queue/reports/${slug}_report.yaml`,
      ];
    default:
      return [];
  }
}

// =============================================================================
// チェックポイント構築
// =============================================================================

/**
 * 指定 slug のチェックポイントオブジェクトを構築する。
 *
 * @param {string} slug
 * @param {string} baseDir - プロジェクトルートディレクトリ
 * @returns {{ checkpoint: object } | null}
 */
function buildCheckpoint(slug, baseDir) {
  // panes.yaml を読む
  const panesPath = path.join(baseDir, 'config', 'panes.yaml');
  let panes;
  try {
    panes = parsePanesYaml(fs.readFileSync(panesPath, 'utf-8'));
  } catch (e) {
    process.stderr.write(`警告: panes.yaml が読めません: ${e.message}\n`);
    return null;
  }

  // roster.yaml を読む
  const rosterPath = path.join(baseDir, 'cast', 'roster.yaml');
  let roster = [];
  try {
    roster = parseRosterYaml(fs.readFileSync(rosterPath, 'utf-8'));
  } catch (e) {
    process.stderr.write(`警告: roster.yaml が読めません: ${e.message}\n`);
  }

  // role を解決
  const role = resolveRole(slug, panes, roster);
  if (role === null) {
    return null;
  }

  // コンテキストファイルを収集
  const contextFiles = collectContextFiles(role, slug);

  // タスク情報を抽出
  let currentTask = null;
  if (role === 'cast' || role === 'reviewer') {
    const taskPath = path.join(baseDir, 'queue', 'tasks', `${slug}.yaml`);
    try {
      const taskContent = fs.readFileSync(taskPath, 'utf-8');
      currentTask = parseTaskYaml(taskContent);
    } catch {
      // ファイルが存在しない場合は null
    }
  } else if (role === 'director' || role === 'producer') {
    // director/producer は producer_to_director.yaml から情報を取得
    const p2dPath = path.join(baseDir, 'queue', 'producer_to_director.yaml');
    try {
      const p2dContent = fs.readFileSync(p2dPath, 'utf-8');
      currentTask = parseTaskYaml(p2dContent);
    } catch {
      // ファイルが存在しない場合は null
    }
  }

  // タイムスタンプを取得
  let timestamp;
  try {
    timestamp = execSync('date "+%Y-%m-%dT%H:%M:%S"', { encoding: 'utf-8' }).trim();
  } catch {
    // date コマンドが使えない場合のフォールバック
    timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, '');
  }

  return {
    checkpoint: {
      slug,
      role,
      unit: null,  // v3.0 で units.yaml 導入後に解決する
      current_task: currentTask,
      pending_decisions: [],
      last_action: null,
      next_action: null,
      context_files: contextFiles,
      timestamp,
    },
  };
}

// =============================================================================
// YAML シリアライザー
// =============================================================================

/**
 * チェックポイントオブジェクトを YAML 文字列にシリアライズする。
 * 設計書のフォーマットに厳密に従う。
 *
 * @param {{ checkpoint: object }} data
 * @returns {string}
 */
function serializeCheckpointYaml(data) {
  const cp = data.checkpoint;
  const lines = [];

  lines.push(`# checkpoints/${cp.slug}.yaml`);
  lines.push('checkpoint:');
  lines.push(`  slug: ${cp.slug}`);
  lines.push(`  role: ${cp.role}`);
  lines.push(`  unit: ${cp.unit === null ? 'null' : cp.unit}`);

  if (cp.current_task === null) {
    lines.push('  current_task: null');
  } else {
    lines.push('  current_task:');
    lines.push(`    id: "${cp.current_task.id}"`);
    lines.push(`    title: "${cp.current_task.title.replace(/"/g, '\\"')}"`);
    lines.push(`    status: ${cp.current_task.status}`);
  }

  lines.push('  pending_decisions: []');

  if (cp.last_action === null) {
    lines.push('  last_action: null');
  } else {
    lines.push(`  last_action: "${cp.last_action.replace(/"/g, '\\"')}"`);

  }

  if (cp.next_action === null) {
    lines.push('  next_action: null');
  } else {
    lines.push(`  next_action: "${cp.next_action.replace(/"/g, '\\"')}"`);
  }

  lines.push('  context_files:');
  for (const file of cp.context_files) {
    lines.push(`    - ${file}`);
  }

  lines.push(`  timestamp: ${cp.timestamp}`);
  lines.push('');

  return lines.join('\n');
}

// =============================================================================
// CLI: 全 slug リストの取得
// =============================================================================

/**
 * panes.yaml と roster.yaml から全 slug のリストを返す。
 * producer, director, + cast メンバー全員。
 *
 * @param {string} baseDir
 * @returns {string[]}
 */
function getAllSlugs(baseDir) {
  const slugs = ['producer', 'director'];

  const panesPath = path.join(baseDir, 'config', 'panes.yaml');
  try {
    const panes = parsePanesYaml(fs.readFileSync(panesPath, 'utf-8'));
    for (const slug of Object.keys(panes.cast)) {
      slugs.push(slug);
    }
  } catch (e) {
    process.stderr.write(`警告: panes.yaml が読めません: ${e.message}\n`);
  }

  return slugs;
}

// =============================================================================
// メインロジック（CLI として実行時）
// =============================================================================

function main() {
  const args = process.argv.slice(2);

  // --base-dir オプションを抽出
  let baseDir = process.cwd();
  const baseDirIdx = args.indexOf('--base-dir');
  if (baseDirIdx !== -1 && args[baseDirIdx + 1]) {
    baseDir = args[baseDirIdx + 1];
    args.splice(baseDirIdx, 2);
  }

  // checkpoints/ ディレクトリを自動作成
  const checkpointsDir = path.join(baseDir, 'checkpoints');
  if (!fs.existsSync(checkpointsDir)) {
    fs.mkdirSync(checkpointsDir, { recursive: true });
  }

  // --snapshot <slug>
  const snapshotIdx = args.indexOf('--snapshot');
  if (snapshotIdx !== -1) {
    const slug = args[snapshotIdx + 1];
    if (!slug) {
      process.stderr.write('[checkpoint] --snapshot には slug が必要です\n');
      process.exit(1);
    }

    const cp = buildCheckpoint(slug, baseDir);
    if (cp === null) {
      process.stderr.write(`[checkpoint] slug "${slug}" が見つかりません\n`);
      process.exit(1);
    }

    const yaml = serializeCheckpointYaml(cp);
    const outPath = path.join(checkpointsDir, `${slug}.yaml`);
    fs.writeFileSync(outPath, yaml);
    process.stdout.write(`checkpoints/${slug}.yaml を保存しました\n`);
    process.exit(0);
  }

  // --snapshot-all
  if (args.includes('--snapshot-all')) {
    const slugs = getAllSlugs(baseDir);
    let count = 0;

    for (const slug of slugs) {
      const cp = buildCheckpoint(slug, baseDir);
      if (cp === null) {
        process.stderr.write(`警告: slug "${slug}" のチェックポイント作成をスキップ\n`);
        continue;
      }

      const yaml = serializeCheckpointYaml(cp);
      const outPath = path.join(checkpointsDir, `${slug}.yaml`);
      fs.writeFileSync(outPath, yaml);
      count++;
    }

    process.stdout.write(`${count} 件のチェックポイントを保存しました\n`);
    process.exit(0);
  }

  // --watch (将来用)
  if (args.includes('--watch')) {
    process.stderr.write('[checkpoint] --watch は未実装です\n');
    process.exit(1);
  }

  // 引数なし
  process.stderr.write(`使用法:
  node checkpoint.js --snapshot <slug> [--base-dir <dir>]
  node checkpoint.js --snapshot-all [--base-dir <dir>]
  node checkpoint.js --watch (未実装)
`);
  process.exit(1);
}

// =============================================================================
// エクスポート（テスト用）+ メイン実行
// =============================================================================

module.exports = {
  parsePanesYaml,
  parseRosterYaml,
  parseTaskYaml,
  parseYamlValue,
  resolveRole,
  collectContextFiles,
  buildCheckpoint,
  serializeCheckpointYaml,
  getAllSlugs,
};

// 直接実行時のみ main() を呼ぶ
if (require.main === module) {
  main();
}
