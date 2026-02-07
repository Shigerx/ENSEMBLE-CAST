/**
 * Stage Manager - router.js
 * ユニット間メッセージルーティング
 *
 * queue/inter_unit/ のYAMLファイルを監視し、
 * 新しいメッセージ（status: unread）を検知して宛先ペインへ配信する。
 *
 * これにより LP や Director が直接 send-keys を管理する必要がなくなる。
 * メッセージを YAML に書くだけで、ルーティングは Stage Manager が行う。
 *
 * 外部依存なし（Node.js 標準ライブラリのみ）。
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execSync, execFileSync } = require('node:child_process');

// =============================================================================
// panes.yaml パーサー（v3 units 構造対応）
// =============================================================================

/**
 * panes.yaml をパースする。
 * v2 形式:
 *   producer: "%0"
 *   director: "%1"
 *   cast:
 *     botan: "%2"
 *
 * v3 形式:
 *   producer: "%0"
 *   line_producer: "%1"
 *   units:
 *     frontend:
 *       director: "%2"
 *       cast:
 *         nene: "%3"
 *     backend:
 *       director: "%5"
 *       cast:
 *         rusty: "%6"
 *
 * @param {string} yamlStr
 * @returns {Map<string, string>} slug → pane_id のマッピング
 */
function parsePanesYaml(yamlStr) {
  const mapping = new Map();
  const lines = yamlStr.split('\n');

  // 各行のインデントレベルとキー・値を追跡するためのステート
  let currentUnit = null;
  let inUnits = false;
  let inCast = false;
  let castIndent = 0;

  for (const line of lines) {
    // コメント行・空行をスキップ
    if (/^\s*#/.test(line) || /^\s*$/.test(line)) continue;

    const indent = line.match(/^(\s*)/)[1].length;

    // トップレベル（インデント0）: producer, director, line_producer, units, cast
    if (indent === 0) {
      inUnits = false;
      inCast = false;
      currentUnit = null;

      // "key: "%N"" 形式のトップレベルキー
      const topMatch = line.match(/^(\w[\w_]*):\s*"([^"]+)"/);
      if (topMatch) {
        mapping.set(topMatch[1], topMatch[2]);
        continue;
      }

      // "units:" セクション開始
      if (/^units:\s*$/.test(line)) {
        inUnits = true;
        continue;
      }

      // "cast:" セクション開始（v2 形式）
      if (/^cast:\s*$/.test(line)) {
        inCast = true;
        castIndent = 2;
        continue;
      }
      continue;
    }

    // v2 形式: cast セクション内のエントリ
    if (inCast && !inUnits && indent >= castIndent) {
      const castEntry = line.match(/^\s+(\w[\w_]*):\s*"([^"]+)"/);
      if (castEntry) {
        mapping.set(castEntry[1], castEntry[2]);
        continue;
      }
    }

    // v3 形式: units セクション内
    if (inUnits) {
      // ユニット名（インデント2）: "  frontend:"
      if (indent === 2) {
        const unitMatch = line.match(/^\s{2}(\w[\w_]*):\s*$/);
        if (unitMatch) {
          currentUnit = unitMatch[1];
          inCast = false;
          continue;
        }

        // ユニットを抜けた場合
        if (/^\s{2}\S/.test(line) && !line.match(/^\s{2}(\w[\w_]*):\s*$/)) {
          currentUnit = null;
          inCast = false;
        }
      }

      // ユニット内の director（インデント4）: "    director: "%2""
      if (currentUnit && indent === 4) {
        const dirMatch = line.match(/^\s{4}director:\s*"([^"]+)"/);
        if (dirMatch) {
          // ユニットの director は "director_<unit>" として登録するのではなく
          // units 内の director はユニット名でも引けるようにする
          // ただし slug として使われるのは "director" が多いため、
          // ユニット名付きのキーも登録する
          const directorSlug = `director_${currentUnit}`;
          mapping.set(directorSlug, dirMatch[1]);
          inCast = false;
          continue;
        }

        // "    cast:" セクション開始
        if (/^\s{4}cast:\s*$/.test(line)) {
          inCast = true;
          castIndent = 6;
          continue;
        }
      }

      // ユニット内の cast メンバー（インデント6）
      if (currentUnit && inCast && indent >= castIndent) {
        const castEntry = line.match(/^\s+(\w[\w_]*):\s*"([^"]+)"/);
        if (castEntry) {
          mapping.set(castEntry[1], castEntry[2]);
          continue;
        }
      }
    }
  }

  return mapping;
}

// =============================================================================
// YAML 値パーサー
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
// メッセージYAMLパーサー
// =============================================================================

/**
 * queue/inter_unit/ のメッセージYAMLをパースする。
 *
 * 形式:
 *   messages:
 *     - id: IU-001
 *       from: { role: director, slug: director_frontend }
 *       to: { role: director, slug: director_backend, unit: backend }
 *       type: task_dependency
 *       payload:
 *         description: "..."
 *       timestamp: "2026-02-07T12:00:00"
 *       status: unread
 *
 * @param {string} yamlStr
 * @returns {Array<{id: string, to: {slug: string}, status: string, _lineRange: {statusLine: number}}>}
 */
function parseMessageYaml(yamlStr) {
  const messages = [];
  const lines = yamlStr.split('\n');
  let inMessages = false;
  let currentMsg = null;
  let inTo = false;
  let inMultilineBlock = false;
  let multilineBaseIndent = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // コメント行をスキップ
    if (/^\s*#/.test(line)) continue;

    // 複数行ブロックのスキップ
    if (inMultilineBlock) {
      if (/^\s*$/.test(line)) continue;
      const currentIndent = line.match(/^(\s*)/)[1].length;
      if (currentIndent >= multilineBaseIndent) continue;
      inMultilineBlock = false;
    }

    if (/^\s*$/.test(line)) continue;

    // messages: [] → 空
    if (/^messages:\s*\[\]/.test(line)) {
      return [];
    }

    // messages: セクション開始
    if (/^messages:\s*$/.test(line)) {
      inMessages = true;
      continue;
    }

    // トップレベルの別キー → messages セクション終了
    if (inMessages && /^\S/.test(line) && !line.startsWith(' ')) {
      inMessages = false;
      continue;
    }

    if (!inMessages) continue;

    // 配列アイテム開始: "  - id: IU-001"
    const arrayItemMatch = line.match(/^\s+-\s+(\w[\w_]*):\s*(.*)/);
    if (arrayItemMatch) {
      // 新しいメッセージ開始
      if (currentMsg && currentMsg.id) {
        messages.push(currentMsg);
      }
      currentMsg = { _lineRange: {} };
      inTo = false;
      const val = arrayItemMatch[2].trim();
      if (val === '|' || val === '>') {
        inMultilineBlock = true;
        multilineBaseIndent = line.match(/^(\s*)/)[1].length + 6;
      } else {
        currentMsg[arrayItemMatch[1]] = parseYamlValue(val);
      }
      continue;
    }

    if (!currentMsg) continue;

    // インラインオブジェクト: "    to: { role: director, slug: xxx, unit: yyy }"
    const inlineObjMatch = line.match(/^\s{4}(\w[\w_]*):\s*\{([^}]+)\}/);
    if (inlineObjMatch) {
      const key = inlineObjMatch[1];
      const obj = {};
      const pairs = inlineObjMatch[2].split(',');
      for (const pair of pairs) {
        const [k, v] = pair.split(':').map((s) => s.trim());
        if (k && v !== undefined) {
          obj[k] = parseYamlValue(v);
        }
      }
      currentMsg[key] = obj;
      if (key === 'to') inTo = false;
      continue;
    }

    // ネストされたオブジェクト開始: "    to:"
    const nestedObjMatch = line.match(/^\s{4}(\w[\w_]*):\s*$/);
    if (nestedObjMatch) {
      const key = nestedObjMatch[1];
      if (key === 'to') {
        currentMsg.to = {};
        inTo = true;
      } else if (key === 'from') {
        currentMsg.from = {};
      } else if (key === 'payload') {
        // payload はスキップ（ルーティングに不要）
        inMultilineBlock = false;
      }
      continue;
    }

    // to の子プロパティ: "      slug: xxx"
    if (inTo) {
      const toPropMatch = line.match(/^\s{6}(\w[\w_]*):\s*(.*)/);
      if (toPropMatch) {
        currentMsg.to[toPropMatch[1]] = parseYamlValue(toPropMatch[2].trim());
        continue;
      }
      // to セクション終了
      if (/^\s{4}\S/.test(line)) {
        inTo = false;
      }
    }

    // 通常のプロパティ: "    key: value"
    const propMatch = line.match(/^\s{4}(\w[\w_]*):\s*(.*)/);
    if (propMatch) {
      const key = propMatch[1];
      const val = propMatch[2].trim();
      if (val === '|' || val === '>') {
        inMultilineBlock = true;
        multilineBaseIndent = line.match(/^(\s*)/)[1].length + 2;
        continue;
      }
      if (key === 'status') {
        currentMsg.status = parseYamlValue(val);
        currentMsg._lineRange.statusLine = i;
      } else {
        currentMsg[key] = parseYamlValue(val);
      }
      continue;
    }
  }

  // 最後のメッセージを追加
  if (currentMsg && currentMsg.id) {
    messages.push(currentMsg);
  }

  return messages;
}

// =============================================================================
// メッセージステータス更新
// =============================================================================

/**
 * YAMLファイル内の特定行の status を更新する。
 * 行番号ベースの置換で、パーサーに頼らない堅牢な方法。
 *
 * @param {string} filePath
 * @param {number} statusLine - 0ベースの行番号
 * @param {string} oldStatus
 * @param {string} newStatus
 * @returns {boolean} 更新成功
 */
function updateMessageStatus(filePath, statusLine, oldStatus, newStatus) {
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    const lines = content.split('\n');

    if (statusLine < 0 || statusLine >= lines.length) {
      return false;
    }

    const line = lines[statusLine];
    // status: <oldStatus> を status: <newStatus> に置換
    const escaped = oldStatus.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const pattern = new RegExp(`(\\s+status:\\s*)${escaped}(\\s*$)`);
    if (!pattern.test(line)) {
      return false;
    }

    lines[statusLine] = line.replace(pattern, `$1${newStatus}$2`);
    fs.writeFileSync(filePath, lines.join('\n'));
    return true;
  } catch (e) {
    log(`ステータス更新エラー (${filePath}): ${e.message}`);
    return false;
  }
}

// =============================================================================
// 宛先ペインID解決
// =============================================================================

/**
 * メッセージの to.slug からペインIDを解決する。
 *
 * @param {string} slug - 宛先の slug
 * @param {Map<string, string>} panesMap - parsePanesYaml の結果
 * @returns {string|null} ペインID（%N形式）、見つからなければ null
 */
function resolveTargetPane(slug, panesMap) {
  if (!slug || !panesMap) return null;
  return panesMap.get(slug) || null;
}

// =============================================================================
// Busy/Idle チェック
// =============================================================================

const BUSY_PATTERNS = /thinking|Effecting|Boondoggling|Puzzling|Calculating|Fermenting|Crunching|Esc to interrupt/;
const IDLE_PATTERNS = /❯ |bypass permissions on/;

/**
 * ペインの Busy/Idle 状態をチェックする。
 *
 * @param {string} paneId - tmux ペインID（%N形式）
 * @returns {'idle'|'busy'|'unknown'}
 */
function checkPaneStatus(paneId) {
  if (!/^%\d+$/.test(paneId)) {
    log(`無効なペインID形式: ${paneId}`);
    return 'unknown';
  }
  try {
    const output = execFileSync('tmux', ['capture-pane', '-t', paneId, '-p'], {
      encoding: 'utf-8',
      timeout: 5000,
    });
    const tail = output.split('\n').slice(-20).join('\n');

    if (IDLE_PATTERNS.test(tail)) return 'idle';
    if (BUSY_PATTERNS.test(tail)) return 'busy';
    return 'idle'; // パターンにマッチしない → Idle扱い
  } catch {
    return 'unknown';
  }
}

/**
 * Busy/Idle チェック付きの配信試行。
 * 最大 maxRetries 回、retryInterval ミリ秒間隔でリトライ。
 *
 * @param {string} paneId
 * @param {object} [opts]
 * @param {number} [opts.maxRetries=3]
 * @param {number} [opts.retryInterval=30000]
 * @param {function} [opts.checkFn] - テスト用: checkPaneStatus の代替
 * @param {function} [opts.sleepFn] - テスト用: sleep の代替
 * @returns {Promise<boolean>} Idle になったら true、全て Busy なら false
 */
async function waitForIdle(paneId, opts = {}) {
  const maxRetries = opts.maxRetries ?? 3;
  const retryInterval = opts.retryInterval ?? 30000;
  const checkFn = opts.checkFn ?? checkPaneStatus;
  const sleepFn = opts.sleepFn ?? ((ms) => new Promise((r) => setTimeout(r, ms)));

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    const status = checkFn(paneId);
    if (status === 'idle' || status === 'unknown') {
      return true;
    }
    // busy の場合、最後の試行でなければ待つ
    if (attempt < maxRetries - 1) {
      await sleepFn(retryInterval);
    }
  }

  return false;
}

// =============================================================================
// メッセージ配信
// =============================================================================

/**
 * send-message.sh を使って宛先ペインを起床する。
 *
 * @param {string} paneId - 宛先ペインID
 * @param {string} message - 起床メッセージ
 * @param {string} baseDir - プロジェクトルート
 * @returns {boolean} 送信成功
 */
function deliverMessage(paneId, message, baseDir) {
  const scriptPath = path.join(baseDir, 'scripts', 'send-message.sh');
  try {
    execFileSync('bash', [scriptPath, paneId, message], {
      encoding: 'utf-8',
      timeout: 10000,
      cwd: baseDir,
      env: { ...process.env, ENSEMBLE_ROOT: baseDir },
    });
    return true;
  } catch (e) {
    log(`配信エラー (${paneId}): ${e.message}`);
    return false;
  }
}

// =============================================================================
// ログ出力
// =============================================================================

/**
 * タイムスタンプ付きログ出力
 * @param {string} msg
 */
function log(msg) {
  const ts = new Date().toISOString().replace(/\.\d{3}Z$/, '');
  process.stderr.write(`[router ${ts}] ${msg}\n`);
}

// =============================================================================
// メッセージ処理（1ファイル分）
// =============================================================================

/**
 * 1つのメッセージYAMLファイルを処理する。
 * unread メッセージを検出し、宛先に配信する。
 *
 * @param {string} filePath - YAMLファイルのフルパス
 * @param {Map<string, string>} panesMap
 * @param {string} baseDir
 * @param {object} [opts] - テスト用オプション
 * @param {function} [opts.waitForIdleFn]
 * @param {function} [opts.deliverFn]
 * @returns {Promise<{delivered: number, skipped: number, errors: number}>}
 */
async function processMessageFile(filePath, panesMap, baseDir, opts = {}) {
  const waitForIdleFn = opts.waitForIdleFn ?? waitForIdle;
  const deliverFn = opts.deliverFn ?? deliverMessage;

  const stats = { delivered: 0, skipped: 0, errors: 0 };

  let content;
  try {
    content = fs.readFileSync(filePath, 'utf-8');
  } catch (e) {
    log(`ファイル読み込みエラー: ${filePath}: ${e.message}`);
    stats.errors++;
    return stats;
  }

  const messages = parseMessageYaml(content);
  const fileName = path.basename(filePath);

  for (const msg of messages) {
    // unread 以外はスキップ
    if (msg.status !== 'unread') continue;

    // 宛先 slug の取得
    const toSlug = msg.to && msg.to.slug;
    if (!toSlug) {
      log(`メッセージ ${msg.id}: 宛先 slug がありません`);
      stats.errors++;
      continue;
    }

    // ペインID解決
    const paneId = resolveTargetPane(toSlug, panesMap);
    if (!paneId) {
      log(`メッセージ ${msg.id}: 宛先 "${toSlug}" が panes.yaml に見つかりません`);
      stats.errors++;
      continue;
    }

    // Busy/Idle チェック
    const isIdle = await waitForIdleFn(paneId, opts);
    if (!isIdle) {
      log(`メッセージ ${msg.id}: 宛先 "${toSlug}" (${paneId}) は Busy のためスキップ`);
      stats.skipped++;
      continue;
    }

    // 配信
    const wakeMsg = `新しいユニット間メッセージあり: queue/inter_unit/${fileName}`;
    const ok = deliverFn(paneId, wakeMsg, baseDir);
    if (ok) {
      // ステータス更新: unread → delivered
      const updated = updateMessageStatus(
        filePath,
        msg._lineRange.statusLine,
        'unread',
        'delivered'
      );
      if (updated) {
        log(`メッセージ ${msg.id} → ${toSlug} (${paneId}) に配信完了`);
        stats.delivered++;
      } else {
        log(`メッセージ ${msg.id}: ステータス更新に失敗`);
        stats.errors++;
      }
    } else {
      log(`メッセージ ${msg.id}: 配信に失敗`);
      stats.errors++;
    }
  }

  return stats;
}

// =============================================================================
// ファイル監視
// =============================================================================

/**
 * queue/inter_unit/ ディレクトリを監視し、変更があったファイルを処理する。
 *
 * @param {string} baseDir - プロジェクトルート
 * @param {object} [opts] - テスト用オプション
 * @returns {{ close: function }} 停止用ハンドル
 */
function startWatcher(baseDir, opts = {}) {
  const interUnitDir = path.join(baseDir, 'queue', 'inter_unit');

  // ディレクトリが存在しなければ作成
  if (!fs.existsSync(interUnitDir)) {
    fs.mkdirSync(interUnitDir, { recursive: true });
  }

  // panes.yaml を読み込み
  const panesPath = path.join(baseDir, 'config', 'panes.yaml');
  let panesMap;
  try {
    panesMap = parsePanesYaml(fs.readFileSync(panesPath, 'utf-8'));
  } catch (e) {
    log(`panes.yaml 読み込みエラー: ${e.message}`);
    process.exit(1);
  }

  log(`監視開始: ${interUnitDir}`);
  log(`ペインマッピング: ${panesMap.size} エントリ`);

  // デバウンス用: ファイルごとに最後の処理時刻を記録
  const lastProcessed = new Map();
  const DEBOUNCE_MS = 1000;

  // 処理中フラグ（同一ファイルの重複処理防止）
  const processing = new Set();

  const watcher = fs.watch(interUnitDir, { persistent: true }, async (eventType, filename) => {
    // YAML ファイルのみ対象
    if (!filename || !filename.endsWith('.yaml')) return;
    // TEMPLATE.yaml は無視
    if (filename === 'TEMPLATE.yaml') return;

    const filePath = path.join(interUnitDir, filename);

    // デバウンス
    const now = Date.now();
    const lastTime = lastProcessed.get(filename) || 0;
    if (now - lastTime < DEBOUNCE_MS) return;
    lastProcessed.set(filename, now);

    // 重複処理防止
    if (processing.has(filename)) return;
    processing.add(filename);

    try {
      // ファイルが存在するか確認（削除イベントの可能性）
      if (!fs.existsSync(filePath)) return;

      // panes.yaml を再読み込み（ペイン構成が変わる可能性）
      try {
        panesMap = parsePanesYaml(fs.readFileSync(panesPath, 'utf-8'));
      } catch {
        // 読み込みに失敗しても既存のマッピングで続行
      }

      const stats = await processMessageFile(filePath, panesMap, baseDir, opts);
      if (stats.delivered > 0 || stats.errors > 0) {
        log(`${filename}: 配信=${stats.delivered}, スキップ=${stats.skipped}, エラー=${stats.errors}`);
      }
    } catch (e) {
      log(`ファイル処理エラー (${filename}): ${e.message}`);
    } finally {
      processing.delete(filename);
    }
  });

  // 起動時に既存の unread メッセージをスキャン
  const initialScan = async () => {
    try {
      const files = fs.readdirSync(interUnitDir)
        .filter((f) => f.endsWith('.yaml') && f !== 'TEMPLATE.yaml');

      for (const file of files) {
        const filePath = path.join(interUnitDir, file);
        try {
          const content = fs.readFileSync(filePath, 'utf-8');
          if (content.includes('status: unread')) {
            const stats = await processMessageFile(filePath, panesMap, baseDir, opts);
            if (stats.delivered > 0 || stats.errors > 0) {
              log(`初期スキャン ${file}: 配信=${stats.delivered}, スキップ=${stats.skipped}, エラー=${stats.errors}`);
            }
          }
        } catch {
          // 個別ファイルのエラーは無視
        }
      }
    } catch (e) {
      log(`初期スキャンエラー: ${e.message}`);
    }
  };

  // 非同期で初期スキャンを実行
  initialScan();

  return {
    close: () => {
      watcher.close();
      log('監視終了');
    },
  };
}

// =============================================================================
// メインロジック（常駐プロセスとして実行時）
// =============================================================================

function main() {
  const args = process.argv.slice(2);

  // --base-dir オプションを抽出
  let baseDir = process.cwd();
  const baseDirIdx = args.indexOf('--base-dir');
  if (baseDirIdx !== -1 && args[baseDirIdx + 1]) {
    baseDir = args[baseDirIdx + 1];
  }

  log(`プロジェクトルート: ${baseDir}`);

  const handle = startWatcher(baseDir);

  // 終了シグナルで停止
  process.on('SIGINT', () => {
    handle.close();
    process.exit(0);
  });
  process.on('SIGTERM', () => {
    handle.close();
    process.exit(0);
  });

  log('ルーター稼働中 (Ctrl+C で停止)');
}

// =============================================================================
// エクスポート（テスト用）+ メイン実行
// =============================================================================

module.exports = {
  parsePanesYaml,
  parseYamlValue,
  parseMessageYaml,
  updateMessageStatus,
  resolveTargetPane,
  checkPaneStatus,
  waitForIdle,
  deliverMessage,
  processMessageFile,
  startWatcher,
};

// 直接実行時のみ main() を呼ぶ
if (require.main === module) {
  main();
}
