/**
 * checkpoint.js テスト
 * Node.js built-in test runner (node:test) + node:assert
 * 外部依存なし
 *
 * テスト用の一時ディレクトリにモックファイルを配置し、
 * --base-dir オプションで基準ディレクトリを差し替える。
 */
'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { execSync } = require('node:child_process');

const {
  parsePanesYaml,
  parseRosterYaml,
  parseTaskYaml,
  resolveRole,
  collectContextFiles,
  buildCheckpoint,
} = require('./checkpoint.js');

// =============================================================================
// ヘルパー: テスト用一時ディレクトリ
// =============================================================================

/**
 * テスト用の一時ディレクトリを作成し、モックファイルを配置する
 */
function createMockBaseDir() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'checkpoint-test-'));
  // 必要なサブディレクトリを作成
  fs.mkdirSync(path.join(tmpDir, 'config'), { recursive: true });
  fs.mkdirSync(path.join(tmpDir, 'cast', 'members', 'botan'), { recursive: true });
  fs.mkdirSync(path.join(tmpDir, 'cast', 'members', 'nene'), { recursive: true });
  fs.mkdirSync(path.join(tmpDir, 'queue', 'tasks'), { recursive: true });
  fs.mkdirSync(path.join(tmpDir, 'queue', 'reports'), { recursive: true });
  fs.mkdirSync(path.join(tmpDir, 'checkpoints'), { recursive: true });
  return tmpDir;
}

function removeDirRecursive(dirPath) {
  fs.rmSync(dirPath, { recursive: true, force: true });
}

/**
 * モック panes.yaml を書き込む
 */
function writePanesYaml(baseDir, content) {
  fs.writeFileSync(
    path.join(baseDir, 'config', 'panes.yaml'),
    content || `producer: "%0"
director: "%1"
cast:
  botan: "%2"
  nene: "%3"
`
  );
}

/**
 * モック roster.yaml を書き込む
 */
function writeRosterYaml(baseDir, content) {
  fs.writeFileSync(
    path.join(baseDir, 'cast', 'roster.yaml'),
    content || `movie: "test-project"
members:
  - slug: "botan"
    character_name: "Botan"
    dev_role: "developer"
    pane_id: "%2"
    status: active

  - slug: "nene"
    character_name: "Nene"
    dev_role: "Reviewer"
    is_reviewer: true
    pane_id: "%3"
    status: active
`
  );
}

/**
 * モックタスクファイルを書き込む
 */
function writeTaskYaml(baseDir, slug, content) {
  fs.writeFileSync(
    path.join(baseDir, 'queue', 'tasks', `${slug}.yaml`),
    content
  );
}

/**
 * モックレポートファイルを書き込む
 */
function writeReportYaml(baseDir, slug, content) {
  fs.writeFileSync(
    path.join(baseDir, 'queue', 'reports', `${slug}_report.yaml`),
    content
  );
}

// =============================================================================
// parsePanesYaml - panes.yaml パーサー
// =============================================================================
describe('parsePanesYaml', () => {
  it('producer, director, cast を正しくパースする', () => {
    const yaml = `producer: "%0"
director: "%1"
cast:
  botan: "%2"
  nene: "%3"
  polka: "%4"
`;
    const result = parsePanesYaml(yaml);
    assert.equal(result.producer, '%0');
    assert.equal(result.director, '%1');
    assert.deepEqual(result.cast, {
      botan: '%2',
      nene: '%3',
      polka: '%4',
    });
  });

  it('cast が空でもクラッシュしない', () => {
    const yaml = `producer: "%0"
director: "%1"
cast:
`;
    const result = parsePanesYaml(yaml);
    assert.equal(result.producer, '%0');
    assert.equal(result.director, '%1');
    assert.deepEqual(result.cast, {});
  });
});

// =============================================================================
// parseRosterYaml - roster.yaml パーサー
// =============================================================================
describe('parseRosterYaml', () => {
  it('members を正しくパースする', () => {
    const yaml = `movie: "test"
members:
  - slug: "botan"
    character_name: "Botan"
    dev_role: "developer"
    pane_id: "%2"
    status: active

  - slug: "nene"
    character_name: "Nene"
    dev_role: "Reviewer"
    is_reviewer: true
    pane_id: "%3"
    status: active
`;
    const result = parseRosterYaml(yaml);
    assert.equal(result.length, 2);
    assert.equal(result[0].slug, 'botan');
    assert.equal(result[0].dev_role, 'developer');
    assert.equal(result[1].slug, 'nene');
    assert.equal(result[1].is_reviewer, true);
  });
});

// =============================================================================
// parseTaskYaml - タスクファイルパーサー
// =============================================================================
describe('parseTaskYaml', () => {
  it('タスク情報を正しく抽出する', () => {
    const yaml = `tasks:
  - id: 1
    title: "TodoList component"
    description: |
      Implement the component.
    priority: high
    status: assigned
    assigned_at: "2026-01-29T21:59:29"
`;
    const result = parseTaskYaml(yaml);
    assert.equal(result.id, '1');
    assert.equal(result.title, 'TodoList component');
    assert.equal(result.status, 'assigned');
  });

  it('文字列IDのタスク (R1等) を正しく抽出する', () => {
    const yaml = `tasks:
  - id: R1
    type: review
    original_task_id: 1
    cast_slug: "botan"
    title: "Review: component"
    status: assigned
`;
    const result = parseTaskYaml(yaml);
    assert.equal(result.id, 'R1');
    assert.equal(result.title, 'Review: component');
    assert.equal(result.status, 'assigned');
  });

  it('空ファイルでも null を返す', () => {
    const result = parseTaskYaml('');
    assert.equal(result, null);
  });

  it('tasks が空でも null を返す', () => {
    const yaml = `tasks: []`;
    const result = parseTaskYaml(yaml);
    assert.equal(result, null);
  });

  it('description の複数行ブロック（|）を正しくスキップする', () => {
    const yaml = `tasks:
  - id: R1
    type: review
    original_task_id: 1
    cast_slug: "botan"
    title: "Review: component"
    description: |
      Cast: botan
      Task: #1

      Check items:
      - TypeScript
      - Tailwind CSS
    files_to_review:
      - "/path/to/file.tsx"
    status: assigned
    assigned_at: "2026-01-29T22:01:25"
`;
    const result = parseTaskYaml(yaml);
    assert.equal(result.id, 'R1');
    assert.equal(result.title, 'Review: component');
    assert.equal(result.status, 'assigned');
  });

  it('description がない場合でも正常にパースする', () => {
    const yaml = `tasks:
  - id: 3
    title: "Simple task"
    status: in_progress
`;
    const result = parseTaskYaml(yaml);
    assert.equal(result.id, '3');
    assert.equal(result.title, 'Simple task');
    assert.equal(result.status, 'in_progress');
  });
});

// =============================================================================
// resolveRole - slug から role を解決
// =============================================================================
describe('resolveRole', () => {
  const panes = {
    producer: '%0',
    director: '%1',
    cast: { botan: '%2', nene: '%3' },
  };
  const roster = [
    { slug: 'botan', dev_role: 'developer', is_reviewer: false },
    { slug: 'nene', dev_role: 'Reviewer', is_reviewer: true },
  ];

  it('producer slug → producer role', () => {
    assert.equal(resolveRole('producer', panes, roster), 'producer');
  });

  it('director slug → director role', () => {
    assert.equal(resolveRole('director', panes, roster), 'director');
  });

  it('cast member (developer) → cast role', () => {
    assert.equal(resolveRole('botan', panes, roster), 'cast');
  });

  it('cast member (reviewer) → reviewer role', () => {
    assert.equal(resolveRole('nene', panes, roster), 'reviewer');
  });

  it('不明な slug → null', () => {
    assert.equal(resolveRole('unknown', panes, roster), null);
  });
});

// =============================================================================
// collectContextFiles - role に応じたコンテキストファイルの収集
// =============================================================================
describe('collectContextFiles', () => {
  it('cast role → タスクとレポートファイル', () => {
    const files = collectContextFiles('cast', 'botan');
    assert.ok(files.includes('queue/tasks/botan.yaml'));
    assert.ok(files.includes('queue/reports/botan_report.yaml'));
  });

  it('reviewer role → タスクとレポートファイル', () => {
    const files = collectContextFiles('reviewer', 'nene');
    assert.ok(files.includes('queue/tasks/nene.yaml'));
    assert.ok(files.includes('queue/reports/nene_report.yaml'));
  });

  it('director role → producer_to_director, dashboard, pending_tasks', () => {
    const files = collectContextFiles('director', 'director');
    assert.ok(files.includes('queue/producer_to_director.yaml'));
    assert.ok(files.includes('dashboard.md'));
    assert.ok(files.includes('queue/pending_tasks.yaml'));
  });

  it('producer role → producer_to_director, dashboard', () => {
    const files = collectContextFiles('producer', 'producer');
    assert.ok(files.includes('queue/producer_to_director.yaml'));
    assert.ok(files.includes('dashboard.md'));
  });
});

// =============================================================================
// buildCheckpoint - チェックポイントオブジェクト構築
// =============================================================================
describe('buildCheckpoint', () => {
  let tmpDir;

  beforeEach(() => {
    tmpDir = createMockBaseDir();
    writePanesYaml(tmpDir);
    writeRosterYaml(tmpDir);
  });

  afterEach(() => {
    removeDirRecursive(tmpDir);
  });

  it('cast member のチェックポイントを正しく構築する', () => {
    writeTaskYaml(tmpDir, 'botan', `tasks:
  - id: 5
    title: "TodoList component"
    status: reviewing
    assigned_at: "2026-01-29T21:59:29"
`);

    const cp = buildCheckpoint('botan', tmpDir);
    assert.equal(cp.checkpoint.slug, 'botan');
    assert.equal(cp.checkpoint.role, 'cast');
    assert.equal(cp.checkpoint.current_task.id, '5');
    assert.equal(cp.checkpoint.current_task.title, 'TodoList component');
    assert.equal(cp.checkpoint.current_task.status, 'reviewing');
    assert.ok(Array.isArray(cp.checkpoint.pending_decisions));
    assert.ok(Array.isArray(cp.checkpoint.context_files));
    assert.ok(cp.checkpoint.timestamp);
  });

  it('reviewer のチェックポイントを正しく構築する', () => {
    writeTaskYaml(tmpDir, 'nene', `tasks:
  - id: R1
    type: review
    title: "Review: component"
    status: assigned
    assigned_at: "2026-02-01T10:00:00"
`);

    const cp = buildCheckpoint('nene', tmpDir);
    assert.equal(cp.checkpoint.slug, 'nene');
    assert.equal(cp.checkpoint.role, 'reviewer');
    assert.equal(cp.checkpoint.current_task.id, 'R1');
    assert.equal(cp.checkpoint.current_task.title, 'Review: component');
    assert.equal(cp.checkpoint.current_task.status, 'assigned');
  });

  it('タスクファイルが存在しない場合でもクラッシュしない', () => {
    // タスクファイルを書き込まない
    const cp = buildCheckpoint('botan', tmpDir);
    assert.equal(cp.checkpoint.slug, 'botan');
    assert.equal(cp.checkpoint.role, 'cast');
    assert.equal(cp.checkpoint.current_task, null);
  });

  it('不明な slug で null を返す', () => {
    const cp = buildCheckpoint('unknown', tmpDir);
    assert.equal(cp, null);
  });
});

// =============================================================================
// CLI 統合テスト（--snapshot, --snapshot-all）
// =============================================================================
describe('CLI integration', () => {
  let tmpDir;
  const scriptPath = path.resolve(__dirname, 'checkpoint.js');

  beforeEach(() => {
    tmpDir = createMockBaseDir();
    writePanesYaml(tmpDir);
    writeRosterYaml(tmpDir);
    writeTaskYaml(tmpDir, 'botan', `tasks:
  - id: 5
    title: "TodoList component"
    status: reviewing
    assigned_at: "2026-01-29T21:59:29"
`);
  });

  afterEach(() => {
    removeDirRecursive(tmpDir);
  });

  it('--snapshot <slug> で正しい YAML が生成される', () => {
    execSync(`node "${scriptPath}" --snapshot botan --base-dir "${tmpDir}"`, {
      encoding: 'utf-8',
    });
    const outputPath = path.join(tmpDir, 'checkpoints', 'botan.yaml');
    assert.ok(fs.existsSync(outputPath), 'checkpoints/botan.yaml が存在するべき');

    const content = fs.readFileSync(outputPath, 'utf-8');
    assert.ok(content.includes('checkpoint:'));
    assert.ok(content.includes('slug: botan'));
    assert.ok(content.includes('role: cast'));
    assert.ok(content.includes('current_task:'));
    assert.ok(content.includes('id: "5"'));
    assert.ok(content.includes('title: "TodoList component"'));
    assert.ok(content.includes('status: reviewing'));
    assert.ok(content.includes('pending_decisions: []'));
    assert.ok(content.includes('context_files:'));
    assert.ok(content.includes('timestamp:'));
  });

  it('不明な slug で exit 1', () => {
    assert.throws(
      () => {
        execSync(
          `node "${scriptPath}" --snapshot unknown --base-dir "${tmpDir}"`,
          { encoding: 'utf-8', stdio: 'pipe' }
        );
      },
      (err) => {
        assert.ok(err.status === 1);
        return true;
      }
    );
  });

  it('タスクファイルが存在しない場合でもクラッシュしない', () => {
    // nene のタスクファイルは書き込んでいない
    execSync(`node "${scriptPath}" --snapshot nene --base-dir "${tmpDir}"`, {
      encoding: 'utf-8',
    });
    const outputPath = path.join(tmpDir, 'checkpoints', 'nene.yaml');
    assert.ok(fs.existsSync(outputPath), 'checkpoints/nene.yaml が存在するべき');

    const content = fs.readFileSync(outputPath, 'utf-8');
    assert.ok(content.includes('slug: nene'));
    assert.ok(content.includes('current_task: null'));
  });

  it('--snapshot-all で全 Agent のスナップショットが生成される', () => {
    execSync(`node "${scriptPath}" --snapshot-all --base-dir "${tmpDir}"`, {
      encoding: 'utf-8',
    });
    // producer, director, botan, nene の 4 ファイル
    assert.ok(fs.existsSync(path.join(tmpDir, 'checkpoints', 'producer.yaml')));
    assert.ok(fs.existsSync(path.join(tmpDir, 'checkpoints', 'director.yaml')));
    assert.ok(fs.existsSync(path.join(tmpDir, 'checkpoints', 'botan.yaml')));
    assert.ok(fs.existsSync(path.join(tmpDir, 'checkpoints', 'nene.yaml')));
  });

  it('checkpoints/ ディレクトリが自動作成される', () => {
    // checkpoints/ ディレクトリを削除
    fs.rmSync(path.join(tmpDir, 'checkpoints'), { recursive: true, force: true });
    assert.ok(!fs.existsSync(path.join(tmpDir, 'checkpoints')));

    execSync(`node "${scriptPath}" --snapshot botan --base-dir "${tmpDir}"`, {
      encoding: 'utf-8',
    });
    assert.ok(fs.existsSync(path.join(tmpDir, 'checkpoints', 'botan.yaml')));
  });

  it('YAML 形式が設計書通りであること', () => {
    execSync(`node "${scriptPath}" --snapshot botan --base-dir "${tmpDir}"`, {
      encoding: 'utf-8',
    });
    const content = fs.readFileSync(
      path.join(tmpDir, 'checkpoints', 'botan.yaml'),
      'utf-8'
    );

    // 設計書のフォーマットを確認:
    // checkpoint: でトップレベル
    // 2スペースインデントで slug, role, current_task, etc.
    const lines = content.split('\n');
    assert.equal(lines[0].trim(), '# checkpoints/botan.yaml');
    assert.ok(lines.some((l) => l === 'checkpoint:'));
    assert.ok(lines.some((l) => l === '  slug: botan'));
    assert.ok(lines.some((l) => l === '  role: cast'));
    assert.ok(lines.some((l) => l === '  unit: null'));
    assert.ok(lines.some((l) => l === '  current_task:'));
    assert.ok(lines.some((l) => l === '    id: "5"'));
    assert.ok(lines.some((l) => l === '    title: "TodoList component"'));
    assert.ok(lines.some((l) => l === '    status: reviewing'));
    assert.ok(lines.some((l) => l === '  pending_decisions: []'));
    assert.ok(lines.some((l) => l.startsWith('  last_action:')));
    assert.ok(lines.some((l) => l.startsWith('  next_action:')));
    assert.ok(lines.some((l) => l === '  context_files:'));
    assert.ok(lines.some((l) => l.match(/^\s{4}- queue\/tasks\/botan\.yaml$/)));
    assert.ok(lines.some((l) => l.match(/^\s+timestamp: \d{4}-\d{2}-\d{2}T/)));
  });
});
