/**
 * guard.js テスト
 * Node.js built-in test runner (node:test) + node:assert
 * 外部依存なし
 */
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const {
  parseSimpleYaml,
  parseValue,
  validateBranchName,
  validateFileOwnership,
  isInternalFile,
} = require('./guard.js');

// =============================================================================
// parseValue - 値パーサー
// =============================================================================
describe('parseValue', () => {
  it('null → null', () => {
    assert.equal(parseValue('null'), null);
  });

  it('~ → null', () => {
    assert.equal(parseValue('~'), null);
  });

  it('true/false → boolean', () => {
    assert.equal(parseValue('true'), true);
    assert.equal(parseValue('false'), false);
  });

  it('整数 → number', () => {
    assert.equal(parseValue('42'), 42);
    assert.equal(parseValue('0'), 0);
    assert.equal(parseValue('-1'), -1);
  });

  it('小数 → number', () => {
    assert.equal(parseValue('3.14'), 3.14);
    assert.equal(parseValue('-0.5'), -0.5);
  });

  it('ダブルクォート文字列 → 引用符除去', () => {
    assert.equal(parseValue('"hello"'), 'hello');
  });

  it('シングルクォート文字列 → 引用符除去', () => {
    assert.equal(parseValue("'world'"), 'world');
  });

  it('空配列 → []', () => {
    assert.deepEqual(parseValue('[]'), []);
  });

  it('プレーン文字列 → そのまま', () => {
    assert.equal(parseValue('active'), 'active');
  });
});

// =============================================================================
// isInternalFile - 内部ファイル判定
// =============================================================================
describe('isInternalFile', () => {
  it('queue/ プレフィックス → true', () => {
    assert.equal(isInternalFile('queue/tasks/botan.yaml'), true);
  });

  it('cast/ プレフィックス → true', () => {
    assert.equal(isInternalFile('cast/roster.yaml'), true);
  });

  it('logs/ プレフィックス → true', () => {
    assert.equal(isInternalFile('logs/activity.log'), true);
  });

  it('config/ プレフィックス → true', () => {
    assert.equal(isInternalFile('config/panes.yaml'), true);
  });

  it('scripts/ プレフィックス → true', () => {
    assert.equal(isInternalFile('scripts/wake-agent.sh'), true);
  });

  it('dashboard.md → true', () => {
    assert.equal(isInternalFile('dashboard.md'), true);
  });

  it('CLAUDE.md → true', () => {
    assert.equal(isInternalFile('CLAUDE.md'), true);
  });

  it('.gitignore → true', () => {
    assert.equal(isInternalFile('.gitignore'), true);
  });

  it('queue で始まるがプレフィックスでない → false', () => {
    assert.equal(isInternalFile('queue-something.ts'), false);
  });

  it('外部プロジェクトファイル → false', () => {
    assert.equal(isInternalFile('src/components/App.tsx'), false);
  });

  it('ルートの未知ファイル → false', () => {
    assert.equal(isInternalFile('unknown.txt'), false);
  });
});

// =============================================================================
// parseSimpleYaml - 簡易YAMLパーサー
// =============================================================================
describe('parseSimpleYaml', () => {
  it('roster.yaml 形式を正しくパースする', () => {
    const yaml = `movie: "ねぽらぼ"
members:
  - slug: "botan"
    character_name: "獅白ぼたん"
    dev_role: "アーキテクト/リード"
    pane_id: "%2"
    status: active

  - slug: "nene"
    character_name: "桃鈴ねね"
    dev_role: "フロントエンド担当"
    pane_id: "%3"
    status: active`;

    const result = parseSimpleYaml(yaml);
    assert.equal(result.movie, 'ねぽらぼ');
    assert.ok(Array.isArray(result.members));
    assert.equal(result.members.length, 2);
    assert.equal(result.members[0].slug, 'botan');
    assert.equal(result.members[1].slug, 'nene');
  });

  it('file_registry.yaml 形式（空 registry）をパースする', () => {
    const yaml = `registry: []`;
    const result = parseSimpleYaml(yaml);
    assert.ok(Array.isArray(result.registry));
    assert.equal(result.registry.length, 0);
  });

  it('file_registry.yaml 形式（エントリあり）をパースする', () => {
    const yaml = `registry:
  - file: "src/components/DueDatePicker.tsx"
    owner: "botan"
    task_id: 1
    type: exclusive
  - file: "src/App.tsx"
    owner: null
    type: shared
    pending_integrator: "polka"`;

    const result = parseSimpleYaml(yaml);
    assert.ok(Array.isArray(result.registry));
    assert.equal(result.registry.length, 2);
    assert.equal(result.registry[0].file, 'src/components/DueDatePicker.tsx');
    assert.equal(result.registry[0].owner, 'botan');
    assert.equal(result.registry[0].task_id, 1);
    assert.equal(result.registry[0].type, 'exclusive');
    assert.equal(result.registry[1].file, 'src/App.tsx');
    assert.equal(result.registry[1].owner, null);
    assert.equal(result.registry[1].type, 'shared');
    assert.equal(result.registry[1].pending_integrator, 'polka');
  });

  it('コメント行を無視する', () => {
    const yaml = `# これはコメント
movie: "test"
# もう一つコメント
members: []`;

    const result = parseSimpleYaml(yaml);
    assert.equal(result.movie, 'test');
    assert.ok(Array.isArray(result.members));
  });
});

// =============================================================================
// validateBranchName - ブランチ名チェック
// =============================================================================
describe('validateBranchName', () => {
  const validSlugs = ['botan', 'nene', 'polka', 'lamy'];

  it('正しい形式の cast ブランチ → pass', () => {
    const result = validateBranchName('cast/botan/1-deadline-feature', validSlugs);
    assert.equal(result.valid, true);
    assert.equal(result.slug, 'botan');
  });

  it('別の cast メンバーのブランチ → pass', () => {
    const result = validateBranchName('cast/nene/42-ui-update', validSlugs);
    assert.equal(result.valid, true);
    assert.equal(result.slug, 'nene');
  });

  it('main ブランチ → pass', () => {
    const result = validateBranchName('main', validSlugs);
    assert.equal(result.valid, true);
    assert.equal(result.slug, null);
  });

  it('director/* ブランチ → pass', () => {
    const result = validateBranchName('director/merge-task-5', validSlugs);
    assert.equal(result.valid, true);
    assert.equal(result.slug, null);
  });

  it('director/deep/nested ブランチ → pass', () => {
    const result = validateBranchName('director/unit/frontend/merge', validSlugs);
    assert.equal(result.valid, true);
    assert.equal(result.slug, null);
  });

  it('不正な形式（cast/ なし）→ reject', () => {
    const result = validateBranchName('feature/something', validSlugs);
    assert.equal(result.valid, false);
    assert.ok(result.reason.length > 0);
  });

  it('不正な形式（slug が roster にない）→ reject', () => {
    const result = validateBranchName('cast/unknown/1-task', validSlugs);
    assert.equal(result.valid, false);
    assert.ok(result.reason.includes('unknown'));
  });

  it('不正な形式（task-id がない）→ reject', () => {
    const result = validateBranchName('cast/botan/', validSlugs);
    assert.equal(result.valid, false);
  });

  it('不正な形式（cast/slug のみ、task-id部なし）→ reject', () => {
    const result = validateBranchName('cast/botan', validSlugs);
    assert.equal(result.valid, false);
  });

  it('不正な形式（task-id が数字で始まらない）→ reject', () => {
    const result = validateBranchName('cast/botan/no-number', validSlugs);
    assert.equal(result.valid, false);
  });

  it('develop ブランチ → reject', () => {
    const result = validateBranchName('develop', validSlugs);
    assert.equal(result.valid, false);
  });

  it('master ブランチ → reject', () => {
    const result = validateBranchName('master', validSlugs);
    assert.equal(result.valid, false);
  });
});

// =============================================================================
// validateFileOwnership - ファイルオーナーシップチェック
// =============================================================================
describe('validateFileOwnership', () => {
  const registry = [
    { file: 'src/components/DueDatePicker.tsx', owner: 'botan', task_id: 1, type: 'exclusive' },
    { file: 'src/App.tsx', owner: null, type: 'shared', pending_integrator: 'polka' },
    { file: 'src/utils/format.ts', owner: 'nene', task_id: 2, type: 'exclusive' },
  ];

  it('owner が一致する → pass', () => {
    const result = validateFileOwnership(
      ['src/components/DueDatePicker.tsx'],
      'botan',
      registry
    );
    assert.equal(result.valid, true);
  });

  it('owner が違う → reject', () => {
    const result = validateFileOwnership(
      ['src/components/DueDatePicker.tsx'],
      'nene',
      registry
    );
    assert.equal(result.valid, false);
    assert.ok(result.violations.length > 0);
    assert.ok(result.violations[0].includes('DueDatePicker'));
  });

  it('shared ファイル → reject（排他でないファイルは統合タスクまで触れない）', () => {
    const result = validateFileOwnership(
      ['src/App.tsx'],
      'botan',
      registry
    );
    assert.equal(result.valid, false);
    assert.ok(result.violations.length > 0);
  });

  it('shared ファイル + pending_integrator 本人 → reject（統合タスク前は触れない）', () => {
    // pending_integrator は将来の統合タスク用。通常のコミットでは触れない
    const result = validateFileOwnership(
      ['src/App.tsx'],
      'polka',
      registry
    );
    assert.equal(result.valid, false);
  });

  it('registry に存在しないファイル → pass（未登録ファイルは自由）', () => {
    const result = validateFileOwnership(
      ['src/new-file.ts'],
      'botan',
      registry
    );
    assert.equal(result.valid, true);
  });

  it('registry が空 → skip（全ファイル pass）', () => {
    const result = validateFileOwnership(
      ['src/anything.ts'],
      'botan',
      []
    );
    assert.equal(result.valid, true);
  });

  it('複数ファイル: 全て owner が一致 → pass', () => {
    const result = validateFileOwnership(
      ['src/components/DueDatePicker.tsx', 'src/new-file.ts'],
      'botan',
      registry
    );
    assert.equal(result.valid, true);
  });

  it('複数ファイル: 一部 owner が違う → reject', () => {
    const result = validateFileOwnership(
      ['src/components/DueDatePicker.tsx', 'src/utils/format.ts'],
      'botan',
      registry
    );
    assert.equal(result.valid, false);
    assert.equal(result.violations.length, 1);
    assert.ok(result.violations[0].includes('format.ts'));
  });

  it('ENSEMBLE-CAST 内部ファイル（queue/）→ チェック対象外（pass）', () => {
    const result = validateFileOwnership(
      ['queue/reports/botan_report.yaml'],
      'botan',
      registry
    );
    assert.equal(result.valid, true);
  });

  it('ENSEMBLE-CAST 内部ファイル（cast/）→ チェック対象外（pass）', () => {
    const result = validateFileOwnership(
      ['cast/members/botan/chronicle.yaml'],
      'botan',
      registry
    );
    assert.equal(result.valid, true);
  });

  it('ENSEMBLE-CAST 内部ファイル（logs/）→ チェック対象外（pass）', () => {
    const result = validateFileOwnership(
      ['logs/botan_status.txt'],
      'botan',
      registry
    );
    assert.equal(result.valid, true);
  });

  it('ENSEMBLE-CAST 内部ファイル（config/）→ チェック対象外（pass）', () => {
    const result = validateFileOwnership(
      ['config/panes.yaml'],
      'botan',
      registry
    );
    assert.equal(result.valid, true);
  });

  it('ENSEMBLE-CAST 内部ファイル（dashboard.md）→ チェック対象外（pass）', () => {
    const result = validateFileOwnership(
      ['dashboard.md'],
      'botan',
      registry
    );
    assert.equal(result.valid, true);
  });

  it('ENSEMBLE-CAST 内部ファイル（scripts/）→ チェック対象外（pass）', () => {
    const result = validateFileOwnership(
      ['scripts/stage-manager/guard.js'],
      'botan',
      registry
    );
    assert.equal(result.valid, true);
  });

  it('slug が null（main / director ブランチ）→ 全ファイル pass', () => {
    const result = validateFileOwnership(
      ['src/components/DueDatePicker.tsx', 'src/App.tsx'],
      null,
      registry
    );
    assert.equal(result.valid, true);
  });
});
