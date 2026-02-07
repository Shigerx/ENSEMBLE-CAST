/**
 * router.js テスト
 * Node.js built-in test runner (node:test) + node:assert
 * 外部依存なし
 *
 * テスト用の一時ディレクトリにモックファイルを配置し、
 * tmux / send-message.sh 呼び出しはモック関数で差し替える。
 */
'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const {
  parsePanesYaml,
  parseYamlValue,
  parseMessageYaml,
  updateMessageStatus,
  resolveTargetPane,
  waitForIdle,
  processMessageFile,
} = require('./router.js');

// =============================================================================
// ヘルパー: テスト用一時ディレクトリ
// =============================================================================

function createMockBaseDir() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'router-test-'));
  fs.mkdirSync(path.join(tmpDir, 'config'), { recursive: true });
  fs.mkdirSync(path.join(tmpDir, 'queue', 'inter_unit'), { recursive: true });
  fs.mkdirSync(path.join(tmpDir, 'scripts'), { recursive: true });
  return tmpDir;
}

function removeDirRecursive(dirPath) {
  fs.rmSync(dirPath, { recursive: true, force: true });
}

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

function writeMessageYaml(baseDir, filename, content) {
  fs.writeFileSync(
    path.join(baseDir, 'queue', 'inter_unit', filename),
    content
  );
}

// =============================================================================
// parseYamlValue - 値パーサー
// =============================================================================
describe('parseYamlValue', () => {
  it('null → null', () => {
    assert.equal(parseYamlValue('null'), null);
  });

  it('~ → null', () => {
    assert.equal(parseYamlValue('~'), null);
  });

  it('true/false → boolean', () => {
    assert.equal(parseYamlValue('true'), true);
    assert.equal(parseYamlValue('false'), false);
  });

  it('整数 → number', () => {
    assert.equal(parseYamlValue('42'), 42);
    assert.equal(parseYamlValue('-1'), -1);
  });

  it('小数 → number', () => {
    assert.equal(parseYamlValue('3.14'), 3.14);
  });

  it('ダブルクォート文字列 → 引用符除去', () => {
    assert.equal(parseYamlValue('"hello"'), 'hello');
  });

  it('シングルクォート文字列 → 引用符除去', () => {
    assert.equal(parseYamlValue("'world'"), 'world');
  });

  it('空配列 → []', () => {
    assert.deepEqual(parseYamlValue('[]'), []);
  });

  it('プレーン文字列 → そのまま', () => {
    assert.equal(parseYamlValue('unread'), 'unread');
  });
});

// =============================================================================
// parsePanesYaml - panes.yaml パーサー
// =============================================================================
describe('parsePanesYaml', () => {
  it('v2 形式を正しくパースする', () => {
    const yaml = `producer: "%0"
director: "%1"
cast:
  botan: "%2"
  nene: "%3"
  polka: "%4"
`;
    const result = parsePanesYaml(yaml);
    assert.equal(result.get('producer'), '%0');
    assert.equal(result.get('director'), '%1');
    assert.equal(result.get('botan'), '%2');
    assert.equal(result.get('nene'), '%3');
    assert.equal(result.get('polka'), '%4');
  });

  it('v3 形式（units 構造）を正しくパースする', () => {
    const yaml = `producer: "%0"
line_producer: "%1"
units:
  frontend:
    director: "%2"
    cast:
      nene: "%3"
      polka: "%4"
  backend:
    director: "%5"
    cast:
      rusty: "%6"
`;
    const result = parsePanesYaml(yaml);
    assert.equal(result.get('producer'), '%0');
    assert.equal(result.get('line_producer'), '%1');
    assert.equal(result.get('director_frontend'), '%2');
    assert.equal(result.get('nene'), '%3');
    assert.equal(result.get('polka'), '%4');
    assert.equal(result.get('director_backend'), '%5');
    assert.equal(result.get('rusty'), '%6');
  });

  it('cast が空でもクラッシュしない', () => {
    const yaml = `producer: "%0"
director: "%1"
cast:
`;
    const result = parsePanesYaml(yaml);
    assert.equal(result.get('producer'), '%0');
    assert.equal(result.get('director'), '%1');
    assert.equal(result.size, 2);
  });

  it('コメント行を無視する', () => {
    const yaml = `# これはコメント
producer: "%0"
# もう一つコメント
director: "%1"
`;
    const result = parsePanesYaml(yaml);
    assert.equal(result.get('producer'), '%0');
    assert.equal(result.get('director'), '%1');
  });
});

// =============================================================================
// parseMessageYaml - メッセージYAMLパーサー
// =============================================================================
describe('parseMessageYaml', () => {
  it('unread メッセージを正しくパースする', () => {
    const yaml = `messages:
  - id: IU-001
    from: { role: director, slug: director_frontend }
    to: { role: director, slug: director_backend, unit: backend }
    type: task_dependency
    timestamp: "2026-02-07T12:00:00"
    status: unread
`;
    const messages = parseMessageYaml(yaml);
    assert.equal(messages.length, 1);
    assert.equal(messages[0].id, 'IU-001');
    assert.equal(messages[0].to.slug, 'director_backend');
    assert.equal(messages[0].to.unit, 'backend');
    assert.equal(messages[0].status, 'unread');
  });

  it('複数メッセージを正しくパースする', () => {
    const yaml = `messages:
  - id: IU-001
    from: { role: director, slug: director_frontend }
    to: { role: director, slug: director_backend, unit: backend }
    type: task_dependency
    timestamp: "2026-02-07T12:00:00"
    status: unread
  - id: IU-002
    from: { role: line_producer, slug: line_producer }
    to: { role: director, slug: director_frontend, unit: frontend }
    type: info
    timestamp: "2026-02-07T12:05:00"
    status: delivered
`;
    const messages = parseMessageYaml(yaml);
    assert.equal(messages.length, 2);
    assert.equal(messages[0].id, 'IU-001');
    assert.equal(messages[0].status, 'unread');
    assert.equal(messages[1].id, 'IU-002');
    assert.equal(messages[1].status, 'delivered');
  });

  it('空メッセージ配列を正しく処理する', () => {
    const yaml = `messages: []`;
    const messages = parseMessageYaml(yaml);
    assert.equal(messages.length, 0);
  });

  it('messages セクションのみの空ファイルを処理する', () => {
    const yaml = `messages:
`;
    const messages = parseMessageYaml(yaml);
    assert.equal(messages.length, 0);
  });

  it('インラインオブジェクト形式の to を正しくパースする', () => {
    const yaml = `messages:
  - id: IU-003
    from: { role: director, slug: director_frontend }
    to: { role: director, slug: botan }
    type: info
    timestamp: "2026-02-07T13:00:00"
    status: unread
`;
    const messages = parseMessageYaml(yaml);
    assert.equal(messages.length, 1);
    assert.equal(messages[0].to.slug, 'botan');
  });

  it('statusLine が正しく記録される', () => {
    const yaml = `messages:
  - id: IU-001
    from: { role: director, slug: director_frontend }
    to: { role: director, slug: director_backend }
    type: task_dependency
    timestamp: "2026-02-07T12:00:00"
    status: unread
`;
    const messages = parseMessageYaml(yaml);
    assert.equal(messages.length, 1);
    assert.ok(typeof messages[0]._lineRange.statusLine === 'number');
    assert.ok(messages[0]._lineRange.statusLine >= 0);
  });
});

// =============================================================================
// resolveTargetPane - 宛先解決テスト
// =============================================================================
describe('resolveTargetPane', () => {
  const panesMap = new Map([
    ['producer', '%0'],
    ['director', '%1'],
    ['botan', '%2'],
    ['nene', '%3'],
    ['director_frontend', '%4'],
    ['director_backend', '%5'],
  ]);

  it('既知の slug → ペインID を返す', () => {
    assert.equal(resolveTargetPane('botan', panesMap), '%2');
  });

  it('director slug → ペインID を返す', () => {
    assert.equal(resolveTargetPane('director', panesMap), '%1');
  });

  it('v3 ユニット director slug → ペインID を返す', () => {
    assert.equal(resolveTargetPane('director_frontend', panesMap), '%4');
  });

  it('存在しない slug → null を返す', () => {
    assert.equal(resolveTargetPane('unknown', panesMap), null);
  });

  it('slug が null → null を返す', () => {
    assert.equal(resolveTargetPane(null, panesMap), null);
  });

  it('slug が undefined → null を返す', () => {
    assert.equal(resolveTargetPane(undefined, panesMap), null);
  });

  it('panesMap が null → null を返す', () => {
    assert.equal(resolveTargetPane('botan', null), null);
  });
});

// =============================================================================
// updateMessageStatus - ステータス更新テスト
// =============================================================================
describe('updateMessageStatus', () => {
  let tmpDir;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'router-status-test-'));
  });

  afterEach(() => {
    removeDirRecursive(tmpDir);
  });

  it('unread → delivered に更新する', () => {
    const filePath = path.join(tmpDir, 'test.yaml');
    const content = `messages:
  - id: IU-001
    to: { slug: botan }
    status: unread
`;
    fs.writeFileSync(filePath, content);

    // status 行は行番号3（0ベース）
    const result = updateMessageStatus(filePath, 3, 'unread', 'delivered');
    assert.equal(result, true);

    const updated = fs.readFileSync(filePath, 'utf-8');
    assert.ok(updated.includes('status: delivered'));
    assert.ok(!updated.includes('status: unread'));
  });

  it('不正な行番号で false を返す', () => {
    const filePath = path.join(tmpDir, 'test.yaml');
    fs.writeFileSync(filePath, 'messages: []\n');

    const result = updateMessageStatus(filePath, 999, 'unread', 'delivered');
    assert.equal(result, false);
  });

  it('oldStatus が一致しない場合は false を返す', () => {
    const filePath = path.join(tmpDir, 'test.yaml');
    const content = `messages:
  - id: IU-001
    status: delivered
`;
    fs.writeFileSync(filePath, content);

    const result = updateMessageStatus(filePath, 2, 'unread', 'delivered');
    assert.equal(result, false);
  });

  it('存在しないファイルで false を返す', () => {
    const result = updateMessageStatus(
      path.join(tmpDir, 'nonexistent.yaml'),
      0,
      'unread',
      'delivered'
    );
    assert.equal(result, false);
  });
});

// =============================================================================
// waitForIdle - Busy/Idle チェックのリトライロジック
// =============================================================================
describe('waitForIdle', () => {
  it('Idle 状態なら即座に true を返す', async () => {
    const checkFn = () => 'idle';
    const result = await waitForIdle('%1', { checkFn });
    assert.equal(result, true);
  });

  it('unknown 状態なら true を返す（Idle扱い）', async () => {
    const checkFn = () => 'unknown';
    const result = await waitForIdle('%1', { checkFn });
    assert.equal(result, true);
  });

  it('Busy → Idle のリトライで true を返す', async () => {
    let callCount = 0;
    const checkFn = () => {
      callCount++;
      return callCount <= 1 ? 'busy' : 'idle';
    };
    const sleepFn = () => Promise.resolve(); // 即座に返す

    const result = await waitForIdle('%1', {
      checkFn,
      sleepFn,
      maxRetries: 3,
    });
    assert.equal(result, true);
    assert.equal(callCount, 2);
  });

  it('3回 Busy で false を返す', async () => {
    let callCount = 0;
    const checkFn = () => {
      callCount++;
      return 'busy';
    };
    const sleepFn = () => Promise.resolve();

    const result = await waitForIdle('%1', {
      checkFn,
      sleepFn,
      maxRetries: 3,
    });
    assert.equal(result, false);
    assert.equal(callCount, 3);
  });

  it('sleep が正しい回数呼ばれる（リトライ間）', async () => {
    let sleepCount = 0;
    const checkFn = () => 'busy';
    const sleepFn = () => {
      sleepCount++;
      return Promise.resolve();
    };

    await waitForIdle('%1', {
      checkFn,
      sleepFn,
      maxRetries: 3,
    });
    // 3回チェック → 2回 sleep（最後の試行後は sleep しない）
    assert.equal(sleepCount, 2);
  });

  it('maxRetries=1 の場合、1回チェックのみ', async () => {
    let callCount = 0;
    const checkFn = () => {
      callCount++;
      return 'busy';
    };
    const sleepFn = () => Promise.resolve();

    const result = await waitForIdle('%1', {
      checkFn,
      sleepFn,
      maxRetries: 1,
    });
    assert.equal(result, false);
    assert.equal(callCount, 1);
  });
});

// =============================================================================
// processMessageFile - メッセージファイル処理（統合テスト）
// =============================================================================
describe('processMessageFile', () => {
  let tmpDir;

  beforeEach(() => {
    tmpDir = createMockBaseDir();
    writePanesYaml(tmpDir);
  });

  afterEach(() => {
    removeDirRecursive(tmpDir);
  });

  it('unread メッセージを正しく配信し delivered に更新する', async () => {
    const msgFile = 'test_msg.yaml';
    writeMessageYaml(tmpDir, msgFile, `messages:
  - id: IU-001
    from: { role: director, slug: director }
    to: { role: cast, slug: botan }
    type: info
    timestamp: "2026-02-07T12:00:00"
    status: unread
`);

    const panesMap = parsePanesYaml(
      fs.readFileSync(path.join(tmpDir, 'config', 'panes.yaml'), 'utf-8')
    );
    const filePath = path.join(tmpDir, 'queue', 'inter_unit', msgFile);

    let deliveredTo = null;
    const stats = await processMessageFile(filePath, panesMap, tmpDir, {
      waitForIdleFn: async () => true,
      deliverFn: (paneId, msg) => {
        deliveredTo = paneId;
        return true;
      },
    });

    assert.equal(stats.delivered, 1);
    assert.equal(stats.skipped, 0);
    assert.equal(stats.errors, 0);
    assert.equal(deliveredTo, '%2'); // botan のペインID

    // ファイルが更新されていることを確認
    const updated = fs.readFileSync(filePath, 'utf-8');
    assert.ok(updated.includes('status: delivered'));
    assert.ok(!updated.includes('status: unread'));
  });

  it('delivered メッセージはスキップする', async () => {
    const msgFile = 'test_msg.yaml';
    writeMessageYaml(tmpDir, msgFile, `messages:
  - id: IU-001
    from: { role: director, slug: director }
    to: { role: cast, slug: botan }
    type: info
    timestamp: "2026-02-07T12:00:00"
    status: delivered
`);

    const panesMap = parsePanesYaml(
      fs.readFileSync(path.join(tmpDir, 'config', 'panes.yaml'), 'utf-8')
    );
    const filePath = path.join(tmpDir, 'queue', 'inter_unit', msgFile);

    const stats = await processMessageFile(filePath, panesMap, tmpDir, {
      waitForIdleFn: async () => true,
      deliverFn: () => true,
    });

    assert.equal(stats.delivered, 0);
    assert.equal(stats.skipped, 0);
    assert.equal(stats.errors, 0);
  });

  it('存在しない宛先の場合はエラーとしてカウントする', async () => {
    const msgFile = 'test_msg.yaml';
    writeMessageYaml(tmpDir, msgFile, `messages:
  - id: IU-001
    from: { role: director, slug: director }
    to: { role: cast, slug: unknown_cast }
    type: info
    timestamp: "2026-02-07T12:00:00"
    status: unread
`);

    const panesMap = parsePanesYaml(
      fs.readFileSync(path.join(tmpDir, 'config', 'panes.yaml'), 'utf-8')
    );
    const filePath = path.join(tmpDir, 'queue', 'inter_unit', msgFile);

    const stats = await processMessageFile(filePath, panesMap, tmpDir, {
      waitForIdleFn: async () => true,
      deliverFn: () => true,
    });

    assert.equal(stats.delivered, 0);
    assert.equal(stats.errors, 1);

    // ステータスは unread のまま
    const content = fs.readFileSync(filePath, 'utf-8');
    assert.ok(content.includes('status: unread'));
  });

  it('Busy で配信スキップした場合 unread のまま残る', async () => {
    const msgFile = 'test_msg.yaml';
    writeMessageYaml(tmpDir, msgFile, `messages:
  - id: IU-001
    from: { role: director, slug: director }
    to: { role: cast, slug: botan }
    type: info
    timestamp: "2026-02-07T12:00:00"
    status: unread
`);

    const panesMap = parsePanesYaml(
      fs.readFileSync(path.join(tmpDir, 'config', 'panes.yaml'), 'utf-8')
    );
    const filePath = path.join(tmpDir, 'queue', 'inter_unit', msgFile);

    const stats = await processMessageFile(filePath, panesMap, tmpDir, {
      waitForIdleFn: async () => false, // 常に Busy
      deliverFn: () => true,
    });

    assert.equal(stats.delivered, 0);
    assert.equal(stats.skipped, 1);

    // ステータスは unread のまま
    const content = fs.readFileSync(filePath, 'utf-8');
    assert.ok(content.includes('status: unread'));
  });

  it('配信失敗時もメッセージは unread のまま残る', async () => {
    const msgFile = 'test_msg.yaml';
    writeMessageYaml(tmpDir, msgFile, `messages:
  - id: IU-001
    from: { role: director, slug: director }
    to: { role: cast, slug: botan }
    type: info
    timestamp: "2026-02-07T12:00:00"
    status: unread
`);

    const panesMap = parsePanesYaml(
      fs.readFileSync(path.join(tmpDir, 'config', 'panes.yaml'), 'utf-8')
    );
    const filePath = path.join(tmpDir, 'queue', 'inter_unit', msgFile);

    const stats = await processMessageFile(filePath, panesMap, tmpDir, {
      waitForIdleFn: async () => true,
      deliverFn: () => false, // 配信失敗
    });

    assert.equal(stats.delivered, 0);
    assert.equal(stats.errors, 1);

    // ステータスは unread のまま
    const content = fs.readFileSync(filePath, 'utf-8');
    assert.ok(content.includes('status: unread'));
  });

  it('to.slug が存在しないメッセージをエラーとして処理する', async () => {
    const msgFile = 'test_msg.yaml';
    writeMessageYaml(tmpDir, msgFile, `messages:
  - id: IU-001
    from: { role: director, slug: director }
    type: info
    timestamp: "2026-02-07T12:00:00"
    status: unread
`);

    const panesMap = parsePanesYaml(
      fs.readFileSync(path.join(tmpDir, 'config', 'panes.yaml'), 'utf-8')
    );
    const filePath = path.join(tmpDir, 'queue', 'inter_unit', msgFile);

    const stats = await processMessageFile(filePath, panesMap, tmpDir, {
      waitForIdleFn: async () => true,
      deliverFn: () => true,
    });

    assert.equal(stats.errors, 1);
  });

  it('複数メッセージの混在（unread + delivered）を正しく処理する', async () => {
    const msgFile = 'test_msg.yaml';
    writeMessageYaml(tmpDir, msgFile, `messages:
  - id: IU-001
    from: { role: director, slug: director }
    to: { role: cast, slug: botan }
    type: info
    timestamp: "2026-02-07T12:00:00"
    status: delivered
  - id: IU-002
    from: { role: director, slug: director }
    to: { role: cast, slug: nene }
    type: info
    timestamp: "2026-02-07T12:05:00"
    status: unread
`);

    const panesMap = parsePanesYaml(
      fs.readFileSync(path.join(tmpDir, 'config', 'panes.yaml'), 'utf-8')
    );
    const filePath = path.join(tmpDir, 'queue', 'inter_unit', msgFile);

    let deliveredPanes = [];
    const stats = await processMessageFile(filePath, panesMap, tmpDir, {
      waitForIdleFn: async () => true,
      deliverFn: (paneId) => {
        deliveredPanes.push(paneId);
        return true;
      },
    });

    assert.equal(stats.delivered, 1);
    assert.equal(deliveredPanes.length, 1);
    assert.equal(deliveredPanes[0], '%3'); // nene のペインID
  });

  it('存在しないファイルパスを処理してもクラッシュしない', async () => {
    const panesMap = parsePanesYaml(
      fs.readFileSync(path.join(tmpDir, 'config', 'panes.yaml'), 'utf-8')
    );
    const filePath = path.join(tmpDir, 'queue', 'inter_unit', 'nonexistent.yaml');

    const stats = await processMessageFile(filePath, panesMap, tmpDir, {
      waitForIdleFn: async () => true,
      deliverFn: () => true,
    });

    assert.equal(stats.errors, 1);
  });
});
