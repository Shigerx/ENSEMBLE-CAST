/**
 * ci.js テスト
 * Node.js built-in test runner (node:test) + node:assert
 * 外部依存なし
 */
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const {
  branchToSlug,
  parseCiConfig,
  getCommandsForLevel,
  formatResults,
  parseProductionYaml,
} = require('./ci.js');

// =============================================================================
// branchToSlug - ブランチ名 → スラッグ変換
// =============================================================================
describe('branchToSlug', () => {
  it('スラッシュをハイフンに変換する', () => {
    assert.equal(branchToSlug('cast/giorno/5-search-ui'), 'cast-giorno-5-search-ui');
  });

  it('スラッシュなしはそのまま返す', () => {
    assert.equal(branchToSlug('main'), 'main');
  });

  it('複数スラッシュをすべて変換する', () => {
    assert.equal(branchToSlug('director/unit/frontend/merge'), 'director-unit-frontend-merge');
  });

  it('空文字列 → 空文字列', () => {
    assert.equal(branchToSlug(''), '');
  });

  it('末尾スラッシュも変換する', () => {
    assert.equal(branchToSlug('cast/giorno/'), 'cast-giorno-');
  });
});

// =============================================================================
// parseCiConfig - ci.yaml パース
// =============================================================================
describe('parseCiConfig', () => {
  it('正常な ci.yaml をパースする', () => {
    const yaml = `level: 2
commands:
  build: "npm run build"
  typecheck: "npx tsc --noEmit"
  test: "npm test"
  e2e: "npx playwright test"`;

    const config = parseCiConfig(yaml);
    assert.equal(config.level, 2);
    assert.equal(config.commands.build, 'npm run build');
    assert.equal(config.commands.typecheck, 'npx tsc --noEmit');
    assert.equal(config.commands.test, 'npm test');
    assert.equal(config.commands.e2e, 'npx playwright test');
  });

  it('level のみの ci.yaml', () => {
    const yaml = `level: 3`;
    const config = parseCiConfig(yaml);
    assert.equal(config.level, 3);
    assert.deepEqual(config.commands, {});
  });

  it('空文字列 → デフォルト値', () => {
    const config = parseCiConfig('');
    assert.equal(config.level, 1);
    assert.deepEqual(config.commands, {});
  });

  it('null → デフォルト値', () => {
    const config = parseCiConfig(null);
    assert.equal(config.level, 1);
    assert.deepEqual(config.commands, {});
  });

  it('コメント行を無視する', () => {
    const yaml = `# CI configuration
level: 4
# commands section
commands:
  build: "npm run build"
  # typecheck is optional
  typecheck: "npx tsc --noEmit"`;

    const config = parseCiConfig(yaml);
    assert.equal(config.level, 4);
    assert.equal(config.commands.build, 'npm run build');
    assert.equal(config.commands.typecheck, 'npx tsc --noEmit');
  });

  it('クォートなしの値もパースする', () => {
    const yaml = `level: 1
commands:
  build: npm run build`;

    const config = parseCiConfig(yaml);
    assert.equal(config.commands.build, 'npm run build');
  });

  it('level が文字列の場合 → 数値に変換', () => {
    const yaml = `level: "3"`;
    const config = parseCiConfig(yaml);
    assert.equal(config.level, 3);
  });
});

// =============================================================================
// getCommandsForLevel - レベルに応じたコマンドリスト
// =============================================================================
describe('getCommandsForLevel', () => {
  const commands = {
    build: 'npm run build',
    typecheck: 'npx tsc --noEmit',
    test: 'npm test',
    e2e: 'npx playwright test',
  };

  it('level 1 → build のみ', () => {
    const result = getCommandsForLevel(1, commands);
    assert.deepEqual(result, [{ name: 'build', command: 'npm run build' }]);
  });

  it('level 2 → build + typecheck', () => {
    const result = getCommandsForLevel(2, commands);
    assert.equal(result.length, 2);
    assert.equal(result[0].name, 'build');
    assert.equal(result[1].name, 'typecheck');
  });

  it('level 3 → build + typecheck + test', () => {
    const result = getCommandsForLevel(3, commands);
    assert.equal(result.length, 3);
    assert.equal(result[0].name, 'build');
    assert.equal(result[1].name, 'typecheck');
    assert.equal(result[2].name, 'test');
  });

  it('level 4 → build + typecheck + test + e2e', () => {
    const result = getCommandsForLevel(4, commands);
    assert.equal(result.length, 4);
    assert.equal(result[0].name, 'build');
    assert.equal(result[1].name, 'typecheck');
    assert.equal(result[2].name, 'test');
    assert.equal(result[3].name, 'e2e');
  });

  it('コマンドが存在しない場合はスキップ', () => {
    const partial = { build: 'npm run build' };
    const result = getCommandsForLevel(3, partial);
    assert.equal(result.length, 1);
    assert.equal(result[0].name, 'build');
  });

  it('コマンドが空オブジェクトの場合 → 空配列', () => {
    const result = getCommandsForLevel(2, {});
    assert.deepEqual(result, []);
  });

  it('level 0 → 空配列', () => {
    const result = getCommandsForLevel(0, commands);
    assert.deepEqual(result, []);
  });

  it('level 5 以上 → level 4 と同じ（全コマンド）', () => {
    const result = getCommandsForLevel(5, commands);
    assert.equal(result.length, 4);
  });
});

// =============================================================================
// formatResults - 結果YAML文字列の生成
// =============================================================================
describe('formatResults', () => {
  it('全パスの結果をフォーマットする', () => {
    const data = {
      branch: 'cast/giorno/5-search-ui',
      commit: 'abc1234',
      timestamp: '2026-02-10T16:00:00',
      level: 2,
      results: {
        build: { status: 'pass', duration_ms: 3200 },
        typecheck: { status: 'pass', duration_ms: 1500 },
      },
      overall: 'pass',
      log_path: 'logs/ci/cast-giorno-5-search-ui.log',
    };

    const yaml = formatResults(data);

    assert.ok(yaml.includes('branch: "cast/giorno/5-search-ui"'));
    assert.ok(yaml.includes('commit: "abc1234"'));
    assert.ok(yaml.includes('timestamp: "2026-02-10T16:00:00"'));
    assert.ok(yaml.includes('level: 2'));
    assert.ok(yaml.includes('overall: "pass"'));
    assert.ok(yaml.includes('log_path: "logs/ci/cast-giorno-5-search-ui.log"'));
    assert.ok(yaml.includes('build:'));
    assert.ok(yaml.includes('status: "pass"'));
    assert.ok(yaml.includes('duration_ms: 3200'));
    assert.ok(yaml.includes('typecheck:'));
  });

  it('失敗結果に summary を含む', () => {
    const data = {
      branch: 'cast/giorno/5-search-ui',
      commit: 'abc1234',
      timestamp: '2026-02-10T16:00:00',
      level: 2,
      results: {
        build: { status: 'pass', duration_ms: 3200 },
        typecheck: { status: 'fail', duration_ms: 800, summary: 'src/App.tsx(42): TS2322 type mismatch' },
      },
      overall: 'fail',
      log_path: 'logs/ci/cast-giorno-5-search-ui.log',
    };

    const yaml = formatResults(data);

    assert.ok(yaml.includes('overall: "fail"'));
    assert.ok(yaml.includes('status: "fail"'));
    assert.ok(yaml.includes('summary: "src/App.tsx(42): TS2322 type mismatch"'));
  });

  it('skip 結果をフォーマットする', () => {
    const data = {
      branch: 'main',
      commit: 'def5678',
      timestamp: '2026-02-10T17:00:00',
      level: 1,
      results: {
        build: { status: 'skip', duration_ms: 0, summary: 'command not configured' },
      },
      overall: 'pass',
      log_path: 'logs/ci/main.log',
    };

    const yaml = formatResults(data);

    assert.ok(yaml.includes('status: "skip"'));
    assert.ok(yaml.includes('summary: "command not configured"'));
  });
});

// =============================================================================
// parseProductionYaml - target_path の取得
// =============================================================================
describe('parseProductionYaml', () => {
  it('target_path が設定されている場合', () => {
    const yaml = `project:
  name: "my-project"
  target_path: "/mnt/c/Users/shige/antigravity/my-project"
  description: "something"`;

    const result = parseProductionYaml(yaml);
    assert.equal(result, '/mnt/c/Users/shige/antigravity/my-project');
  });

  it('target_path が null の場合', () => {
    const yaml = `project:
  name: "flare"
  target_path: null
  description: "something"`;

    const result = parseProductionYaml(yaml);
    assert.equal(result, null);
  });

  it('target_path が存在しない場合 → null', () => {
    const yaml = `project:
  name: "flare"
  description: "something"`;

    const result = parseProductionYaml(yaml);
    assert.equal(result, null);
  });

  it('空文字列 → null', () => {
    const result = parseProductionYaml('');
    assert.equal(result, null);
  });

  it('null → null', () => {
    const result = parseProductionYaml(null);
    assert.equal(result, null);
  });

  it('クォート付き target_path', () => {
    const yaml = `project:
  name: "flare"
  target_path: "C:\\Users\\shige\\projects\\app"`;

    const result = parseProductionYaml(yaml);
    assert.equal(result, 'C:\\Users\\shige\\projects\\app');
  });

  it('target_path がチルダ(~)の場合 → null', () => {
    const yaml = `project:
  name: "flare"
  target_path: ~`;

    const result = parseProductionYaml(yaml);
    assert.equal(result, null);
  });
});
