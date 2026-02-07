/**
 * send-message.sh テスト
 * Node.js built-in test runner (node:test) + node:assert
 * 外部依存なし
 *
 * tmux 操作はモック不可（シェルスクリプト）のため、
 * panes.yaml パース・引数チェック・slug解決をテスト。
 * tmux コマンド自体は --dry-run モードで検証。
 */
const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { execSync, execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

// send-message.sh のパス
const SCRIPT_PATH = path.resolve(__dirname, '..', 'send-message.sh');

// テスト用一時ディレクトリ
let tmpDir;

/**
 * テスト用 panes.yaml を生成
 */
function createMockPanesYaml(content) {
  const configDir = path.join(tmpDir, 'config');
  fs.mkdirSync(configDir, { recursive: true });
  fs.writeFileSync(path.join(configDir, 'panes.yaml'), content, 'utf-8');
}

/**
 * send-message.sh を実行（dry-run モード）
 * @param {string[]} args
 * @param {object} [opts]
 * @returns {{ stdout: string, stderr: string, status: number }}
 */
function runScript(args, opts = {}) {
  const env = {
    ...process.env,
    ENSEMBLE_ROOT: tmpDir,
    SEND_MESSAGE_DRY_RUN: '1',
    ...opts.env,
  };
  try {
    const stdout = execFileSync('bash', [SCRIPT_PATH, ...args], {
      encoding: 'utf-8',
      env,
      cwd: tmpDir,
      timeout: 5000,
    });
    return { stdout, stderr: '', status: 0 };
  } catch (e) {
    return {
      stdout: e.stdout || '',
      stderr: e.stderr || '',
      status: e.status,
    };
  }
}

// =============================================================================
// 引数チェック
// =============================================================================
describe('send-message.sh - 引数チェック', () => {
  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'send-msg-test-'));
    createMockPanesYaml(`producer: "%0"
director: "%1"
cast:
  botan: "%2"
  nene: "%3"
`);
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('引数なしで exit 1', () => {
    const result = runScript([]);
    assert.equal(result.status, 1);
    assert.ok(result.stderr.includes('Usage'));
  });

  it('引数1つだけで exit 1', () => {
    const result = runScript(['director']);
    assert.equal(result.status, 1);
    assert.ok(result.stderr.includes('Usage'));
  });
});

// =============================================================================
// slug名からペインID解決
// =============================================================================
describe('send-message.sh - slug解決', () => {
  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'send-msg-test-'));
    createMockPanesYaml(`producer: "%0"
director: "%1"
cast:
  botan: "%2"
  nene: "%3"
  polka: "%4"
`);
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('トップレベルslug "director" → %1 に解決', () => {
    const result = runScript(['director', 'hello']);
    assert.equal(result.status, 0);
    assert.ok(result.stdout.includes('%1'));
  });

  it('トップレベルslug "producer" → %0 に解決', () => {
    const result = runScript(['producer', 'hello']);
    assert.equal(result.status, 0);
    assert.ok(result.stdout.includes('%0'));
  });

  it('cast slug "botan" → %2 に解決', () => {
    const result = runScript(['botan', 'hello']);
    assert.equal(result.status, 0);
    assert.ok(result.stdout.includes('%2'));
  });

  it('cast slug "nene" → %3 に解決', () => {
    const result = runScript(['nene', 'hello']);
    assert.equal(result.status, 0);
    assert.ok(result.stdout.includes('%3'));
  });

  it('cast slug "polka" → %4 に解決', () => {
    const result = runScript(['polka', 'hello']);
    assert.equal(result.status, 0);
    assert.ok(result.stdout.includes('%4'));
  });

  it('不明なslugで exit 1', () => {
    const result = runScript(['unknown_slug', 'hello']);
    assert.equal(result.status, 1);
    assert.ok(result.stderr.includes('unknown_slug'));
  });

  it('正規表現メタ文字を含むslugで exit 1（インジェクション防止）', () => {
    const result = runScript(['.*', 'hello']);
    assert.equal(result.status, 1);
    assert.ok(result.stderr.includes('不正な slug'));
  });

  it('シェルメタ文字を含むslugで exit 1', () => {
    const result = runScript(['$(whoami)', 'hello']);
    assert.equal(result.status, 1);
  });
});

// =============================================================================
// %ID 直接指定
// =============================================================================
describe('send-message.sh - %ID直接指定', () => {
  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'send-msg-test-'));
    createMockPanesYaml(`producer: "%0"
director: "%1"
`);
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('%5 を直接指定 → そのまま %5 を使用', () => {
    const result = runScript(['%5', 'hello']);
    assert.equal(result.status, 0);
    assert.ok(result.stdout.includes('%5'));
  });

  it('%0 を直接指定 → そのまま %0 を使用', () => {
    const result = runScript(['%0', 'hello']);
    assert.equal(result.status, 0);
    assert.ok(result.stdout.includes('%0'));
  });
});

// =============================================================================
// --check-busy フラグ
// =============================================================================
describe('send-message.sh - --check-busy フラグ', () => {
  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'send-msg-test-'));
    createMockPanesYaml(`producer: "%0"
director: "%1"
cast:
  botan: "%2"
`);
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('--check-busy フラグが dry-run 出力に含まれる', () => {
    const result = runScript(['--check-busy', 'director', 'hello']);
    assert.equal(result.status, 0);
    // dry-run モードでは busy チェックの意図が出力される
    assert.ok(result.stdout.includes('check-busy'));
  });

  it('--check-busy なしでもメッセージ送信は成功する', () => {
    const result = runScript(['director', 'hello']);
    assert.equal(result.status, 0);
    assert.ok(!result.stdout.includes('check-busy'));
  });
});

// =============================================================================
// dry-run 出力でコマンド構成を検証
// =============================================================================
describe('send-message.sh - dry-run コマンド検証', () => {
  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'send-msg-test-'));
    createMockPanesYaml(`producer: "%0"
director: "%1"
cast:
  botan: "%2"
`);
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('送信テキストが正しく渡される', () => {
    const result = runScript(['director', 'テスト送信メッセージ']);
    assert.equal(result.status, 0);
    assert.ok(result.stdout.includes('テスト送信メッセージ'));
  });

  it('2コール send-keys パターンが出力される（テキスト + Enter）', () => {
    const result = runScript(['botan', 'hello world']);
    assert.equal(result.status, 0);
    // dry-run 出力で send-keys テキスト送信と Enter 送信が両方含まれる
    assert.ok(result.stdout.includes('send-keys'));
    assert.ok(result.stdout.includes('Enter'));
  });
});

// =============================================================================
// panes.yaml が存在しない場合
// =============================================================================
describe('send-message.sh - panes.yaml 不在', () => {
  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'send-msg-test-'));
    // panes.yaml を作成しない
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('slug指定時、panes.yaml がないと exit 1', () => {
    const result = runScript(['director', 'hello']);
    assert.equal(result.status, 1);
    assert.ok(result.stderr.includes('panes.yaml'));
  });

  it('%ID直接指定なら panes.yaml 不要で成功', () => {
    const result = runScript(['%1', 'hello']);
    assert.equal(result.status, 0);
  });
});
