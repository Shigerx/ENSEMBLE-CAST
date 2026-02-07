/**
 * Stage Manager - guard.js
 * Git pre-commit hook ロジック
 *
 * ブランチ名・ファイルオーナーシップをプログラム的に強制する。
 * 外部依存なし（Node.js 標準ライブラリのみ）。
 */
'use strict';

const { execSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

// =============================================================================
// ENSEMBLE-CAST 内部ファイルパターン（オーナーシップチェック対象外）
// =============================================================================
const INTERNAL_PREFIXES = [
  'queue/',
  'cast/',
  'logs/',
  'config/',
  'scripts/',
  'instructions/',
  'context/',
  'memory/',
  'plans/',
  'contracts/',
  'checkpoints/',
  'dailies/',
  '.githooks/',
  '.claude/',
  'hooks/',
];

const INTERNAL_FILES = [
  'dashboard.md',
  'CLAUDE.md',
  'README.md',
  '.gitignore',
];

/**
 * ファイルが ENSEMBLE-CAST 内部ファイルかどうかを判定
 * @param {string} filePath
 * @returns {boolean}
 */
function isInternalFile(filePath) {
  // プレフィックスチェック
  for (const prefix of INTERNAL_PREFIXES) {
    if (filePath.startsWith(prefix)) return true;
  }
  // 個別ファイルチェック
  for (const file of INTERNAL_FILES) {
    if (filePath === file) return true;
  }
  return false;
}

// =============================================================================
// 簡易 YAML パーサー
// =============================================================================

/**
 * 簡易 YAML パーサー
 * roster.yaml と file_registry.yaml の構造のみ対応。
 * 汎用 YAML パーサーではない。
 *
 * @param {string} yamlStr
 * @returns {object}
 */
function parseSimpleYaml(yamlStr) {
  const lines = yamlStr.split('\n');
  const result = {};
  let currentKey = null;
  let currentArray = null;
  let currentItem = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // コメント行・空行をスキップ
    if (/^\s*#/.test(line) || /^\s*$/.test(line)) continue;

    // トップレベル: "key: value" or "key:" or "key: []"
    const topMatch = line.match(/^(\w[\w_]*):\s*(.*)/);
    if (topMatch) {
      const key = topMatch[1];
      const val = topMatch[2].trim();

      if (val === '[]') {
        result[key] = [];
        currentKey = key;
        currentArray = result[key];
        currentItem = null;
      } else if (val === '') {
        // 次の行が配列かもしれない
        result[key] = [];
        currentKey = key;
        currentArray = result[key];
        currentItem = null;
      } else {
        // スカラー値
        result[key] = parseValue(val);
        currentKey = key;
        currentArray = null;
        currentItem = null;
      }
      continue;
    }

    // 配列アイテム開始: "  - key: value"
    const arrayItemMatch = line.match(/^\s+-\s+(\w[\w_]*):\s*(.*)/);
    if (arrayItemMatch && currentArray !== null) {
      currentItem = {};
      currentItem[arrayItemMatch[1]] = parseValue(arrayItemMatch[2].trim());
      currentArray.push(currentItem);
      continue;
    }

    // 配列アイテムのプロパティ: "    key: value"
    const propMatch = line.match(/^\s{4,}(\w[\w_]*):\s*(.*)/);
    if (propMatch && currentItem !== null) {
      currentItem[propMatch[1]] = parseValue(propMatch[2].trim());
      continue;
    }
  }

  return result;
}

/**
 * YAML の値をパース
 * @param {string} val
 * @returns {string|number|boolean|null}
 */
function parseValue(val) {
  if (val === 'null' || val === '~') return null;
  if (val === 'true') return true;
  if (val === 'false') return false;
  if (/^-?\d+$/.test(val)) return parseInt(val, 10);
  if (/^-?\d+\.\d+$/.test(val)) return parseFloat(val);
  // 引用符を除去
  if ((val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))) {
    return val.slice(1, -1);
  }
  if (val === '[]') return [];
  return val;
}

// =============================================================================
// ブランチ名バリデーション
// =============================================================================

/**
 * ブランチ名を検証する
 * @param {string} branchName
 * @param {string[]} validSlugs - roster.yaml から取得した有効な slug 一覧
 * @returns {{ valid: boolean, slug: string|null, reason?: string }}
 */
function validateBranchName(branchName, validSlugs) {
  // main ブランチは許可
  if (branchName === 'main') {
    return { valid: true, slug: null };
  }

  // director/* ブランチは許可
  if (branchName.startsWith('director/')) {
    return { valid: true, slug: null };
  }

  // cast/<slug>/<task-id>-* 形式チェック
  const castMatch = branchName.match(/^cast\/([^/]+)\/(\d+-.+)$/);
  if (!castMatch) {
    return {
      valid: false,
      slug: null,
      reason: `ブランチ名が不正です: "${branchName}"。cast/<slug>/<task-id>-<説明> 形式にしてください。(main, director/* も許可)`,
    };
  }

  const slug = castMatch[1];

  // slug が roster に存在するか
  if (!validSlugs.includes(slug)) {
    return {
      valid: false,
      slug: null,
      reason: `slug "${slug}" は roster.yaml に存在しません。有効な slug: ${validSlugs.join(', ')}`,
    };
  }

  return { valid: true, slug };
}

// =============================================================================
// ファイルオーナーシップバリデーション
// =============================================================================

/**
 * コミット対象ファイルのオーナーシップを検証する
 * @param {string[]} files - コミットに含まれるファイルパス一覧
 * @param {string|null} slug - ブランチの slug（main/director の場合は null）
 * @param {Array<{file: string, owner: string|null, type: string}>} registry - file_registry.yaml の registry
 * @returns {{ valid: boolean, violations: string[] }}
 */
function validateFileOwnership(files, slug, registry) {
  // slug が null（main / director ブランチ）→ 全ファイル許可
  if (slug === null) {
    return { valid: true, violations: [] };
  }

  // registry が空 → チェックスキップ
  if (!registry || registry.length === 0) {
    return { valid: true, violations: [] };
  }

  const violations = [];

  for (const file of files) {
    // ENSEMBLE-CAST 内部ファイルはチェック対象外
    if (isInternalFile(file)) continue;

    // registry で該当ファイルを検索
    const entry = registry.find((r) => r.file === file);

    // 未登録ファイルは自由
    if (!entry) continue;

    // shared ファイルはコミット不可（統合タスクまで触れない）
    if (entry.type === 'shared') {
      violations.push(`"${file}" は shared ファイルです。統合タスクまで変更できません。`);
      continue;
    }

    // exclusive ファイルは owner が一致する必要がある
    if (entry.type === 'exclusive' && entry.owner !== slug) {
      violations.push(`"${file}" の owner は "${entry.owner}" です。"${slug}" は変更できません。`);
    }
  }

  return {
    valid: violations.length === 0,
    violations,
  };
}

// =============================================================================
// メインロジック（pre-commit hook として実行時）
// =============================================================================

/**
 * pre-commit hook メイン処理
 * テスト時には呼ばれない。
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
      // detached HEAD（rebase 中等）→ チェックスキップ
      process.stderr.write(`[Stage Manager] detached HEAD 状態のためチェックをスキップします\n`);
      process.exit(0);
    }

    // 2. roster.yaml から有効な slug 一覧を取得
    const rosterPath = path.join(repoRoot, 'cast', 'roster.yaml');
    let validSlugs = [];
    try {
      const rosterContent = fs.readFileSync(rosterPath, 'utf-8');
      const roster = parseSimpleYaml(rosterContent);
      if (roster.members && Array.isArray(roster.members)) {
        validSlugs = roster.members.map((m) => m.slug).filter(Boolean);
      }
    } catch (e) {
      // roster.yaml が読めない場合はブランチ名チェックのみ（slug 検証はスキップ）
      process.stderr.write(`警告: roster.yaml が読めません: ${e.message}\n`);
    }

    // 3. ブランチ名チェック
    const branchResult = validateBranchName(branchName, validSlugs);
    if (!branchResult.valid) {
      process.stderr.write(`[Stage Manager] ブランチ名チェック失敗:\n`);
      process.stderr.write(`  ${branchResult.reason}\n`);
      process.exit(1);
    }

    // 4. コミット対象ファイルを取得
    const stagedFiles = execSync('git diff --cached --name-only', { encoding: 'utf-8' })
      .trim()
      .split('\n')
      .filter(Boolean);

    if (stagedFiles.length === 0) {
      // コミットするファイルがない
      process.exit(0);
    }

    // 5. file_registry.yaml からオーナーシップ情報を取得
    const registryPath = path.join(repoRoot, 'queue', 'file_registry.yaml');
    let registry = [];
    try {
      const registryContent = fs.readFileSync(registryPath, 'utf-8');
      const parsed = parseSimpleYaml(registryContent);
      if (parsed.registry && Array.isArray(parsed.registry)) {
        registry = parsed.registry;
      }
    } catch (e) {
      // file_registry.yaml が読めない場合はオーナーシップチェックをスキップ
      process.stderr.write(`警告: file_registry.yaml が読めません: ${e.message}\n`);
    }

    // 6. ファイルオーナーシップチェック
    const ownerResult = validateFileOwnership(stagedFiles, branchResult.slug, registry);
    if (!ownerResult.valid) {
      process.stderr.write(`[Stage Manager] ファイルオーナーシップチェック失敗:\n`);
      for (const v of ownerResult.violations) {
        process.stderr.write(`  ${v}\n`);
      }
      process.exit(1);
    }

    // ドメイン境界チェック（v3.0 で実装予定）
    // TODO: units.yaml の domain 定義に基づくドメイン境界検証を追加

    // 全チェック通過
    process.exit(0);
  } catch (e) {
    process.stderr.write(`[Stage Manager] 予期しないエラー: ${e.message}\n`);
    process.exit(1);
  }
}

// =============================================================================
// エクスポート（テスト用）+ メイン実行
// =============================================================================

module.exports = {
  parseSimpleYaml,
  parseValue,
  validateBranchName,
  validateFileOwnership,
  isInternalFile,
};

// 直接実行時のみ main() を呼ぶ
if (require.main === module) {
  main();
}
