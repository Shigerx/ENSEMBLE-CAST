#!/usr/bin/env python3
"""ENSEMBLE CAST — Theater Server

Lightweight API server for the Theater Web UI.
Python stdlib only — no pip dependencies.

Usage: python3 scripts/theater-server.py [--port 3939] [--base /path/to/ENSEMBLE-CAST]
"""

import http.server
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlparse, parse_qs

PORT = 3939
BASE = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------------------
# YAML helpers (stdlib only — handles the subset used by ENSEMBLE-CAST)
# ---------------------------------------------------------------------------

def yaml_val(text, key):
    """Extract a simple scalar value for *key* from YAML text."""
    # Handle both "  key:" and "  - key:" (YAML list item)
    m = re.search(rf'^\s*(?:-\s+)?{re.escape(key)}:\s*(.+)$', text, re.MULTILINE)
    if not m:
        return None
    v = m.group(1).strip()
    if (v.startswith('"') and v.endswith('"')) or \
       (v.startswith("'") and v.endswith("'")):
        v = v[1:-1]
    if v in ('null', '~', ''):
        return None
    return v


def yaml_blocks(text, marker='- slug:'):
    """Split a YAML list into blocks starting with *marker*."""
    blocks, cur = [], []
    for line in text.split('\n'):
        if marker in line:
            if cur:
                blocks.append('\n'.join(cur))
            cur = [line]
        elif cur:
            cur.append(line)
    if cur:
        blocks.append('\n'.join(cur))
    return blocks


def parse_episode_yaml(text):
    """Parse an episode YAML file into a dict.

    Handles the specific subset format used by ENSEMBLE-CAST episodes:
      episode: N
      title: "..."
      synopsis: "..."
      scenes:
        - scene: N
          title: "..."
          narration: "..."
          beats:
            - character: slug
              action: "..."
              dialogue: "..."
            - narration: "..."
    """
    result = {}

    # Top-level scalars
    ep_num = yaml_val(text, 'episode')
    result['episode'] = int(ep_num) if ep_num and ep_num.isdigit() else 0
    result['title'] = yaml_val(text, 'title')
    result['synopsis'] = yaml_val(text, 'synopsis')

    # Parse scenes
    scenes = []
    scene_blocks = yaml_blocks(text, '- scene:')
    for sb in scene_blocks:
        scene = {}
        sn = yaml_val(sb, 'scene')
        scene['scene'] = int(sn) if sn and sn.isdigit() else 0
        scene['title'] = yaml_val(sb, 'title')
        scene['narration'] = yaml_val(sb, 'narration')

        # Parse beats within this scene (preserving order of appearance)
        beats = _parse_beats(sb)
        scene['beats'] = beats
        scenes.append(scene)

    result['scenes'] = scenes
    return result


def _parse_beats(scene_text):
    """Parse beat entries from a scene block, preserving order."""
    beats = []
    lines = scene_text.split('\n')
    in_beats = False
    current_beat = None
    beat_indent = 0

    for line in lines:
        stripped = line.strip()

        # Detect the beats: section
        if stripped == 'beats:':
            in_beats = True
            continue

        if not in_beats:
            continue

        # Detect a new beat (list item under beats:)
        # Beats start with "- character:" or "- narration:"
        m_char = re.match(r'^(\s+)-\s+character:\s*(.+)$', line)
        m_narr = re.match(r'^(\s+)-\s+narration:\s*(.+)$', line)

        if m_char:
            if current_beat is not None:
                beats.append(current_beat)
            beat_indent = len(m_char.group(1))
            val = m_char.group(2).strip().strip('"').strip("'")
            current_beat = {'character': val}
        elif m_narr:
            if current_beat is not None:
                beats.append(current_beat)
            beat_indent = len(m_narr.group(1))
            val = m_narr.group(2).strip().strip('"').strip("'")
            current_beat = {'narration': val}
        elif current_beat is not None:
            # Continuation keys within current beat (action, dialogue, narration)
            indent = len(line) - len(line.lstrip())
            if indent <= beat_indent and stripped and not stripped.startswith('-'):
                # Exited beats section (back to scene level)
                in_beats = False
                continue
            m_kv = re.match(r'^\s+(\w+):\s*(.+)$', line)
            if m_kv:
                key = m_kv.group(1)
                val = m_kv.group(2).strip()
                if (val.startswith('"') and val.endswith('"')) or \
                   (val.startswith("'") and val.endswith("'")):
                    val = val[1:-1]
                if val not in ('null', '~', ''):
                    current_beat[key] = val

    if current_beat is not None:
        beats.append(current_beat)

    return beats

# ---------------------------------------------------------------------------
# Data loaders
# ---------------------------------------------------------------------------

def parse_activity_line(line):
    """Parse one activity.log line → dict or None."""
    line = line.strip()
    if not line:
        return None
    # TSV: timestamp \t actor \t event \t message
    parts = line.split('\t')
    if len(parts) >= 4:
        return dict(timestamp=parts[0], actor=parts[1],
                     event=parts[2], message='\t'.join(parts[3:]))
    # Alt: [timestamp] [event] actor: message
    m = re.match(r'\[(.+?)\]\s+\[(\w+)\]\s+(\w+):\s*(.*)', line)
    if m:
        return dict(timestamp=m.group(1), actor=m.group(3),
                     event=m.group(2), message=m.group(4))
    return None


def load_activity(limit=50):
    path = BASE / 'logs' / 'activity.log'
    if not path.exists():
        return []
    entries = []
    for line in path.read_text(encoding='utf-8').strip().split('\n'):
        e = parse_activity_line(line)
        if e:
            entries.append(e)
    return entries[-limit:]


CAST_COLORS = {
    'giorno': '#f0c040', 'bucciarati': '#4a9eff', 'narancia': '#ff6b35',
    'mista': '#8b5cf6', 'abbacchio': '#6b7280',
}

def load_cast():
    roster = BASE / 'cast' / 'roster.yaml'
    if not roster.exists():
        return []
    content = roster.read_text(encoding='utf-8')
    cast = []
    for block in yaml_blocks(content, '- slug:'):
        slug = yaml_val(block, 'slug')
        if not slug:
            continue
        member = dict(
            slug=slug,
            character_name=yaml_val(block, 'character_name') or slug,
            dev_role=yaml_val(block, 'dev_role') or '',
            color=CAST_COLORS.get(slug, '#ffffff'),
            emoji='', ability_name='',
            state='', task_id=None, task_title='',
        )
        # Persona
        pp = BASE / 'cast' / 'members' / slug / 'persona.yaml'
        if pp.exists():
            pc = pp.read_text(encoding='utf-8')
            member['emoji'] = yaml_val(pc, 'emoji') or ''
            member['ability_name'] = yaml_val(pc, 'ability_name') or ''
        # Status
        sp = BASE / 'logs' / f'{slug}_status.txt'
        if sp.exists():
            parts = sp.read_text(encoding='utf-8').strip().split('|')
            member['state'] = parts[0] if parts else ''
        # Current task
        tp = BASE / 'queue' / 'tasks' / f'{slug}.yaml'
        if tp.exists():
            tc = tp.read_text(encoding='utf-8')
            for tb in reversed(yaml_blocks(tc, '- id:')):
                tid = yaml_val(tb, 'id')
                if tid:
                    try:
                        member['task_id'] = int(tid)
                    except (ValueError, TypeError):
                        continue
                    member['task_title'] = yaml_val(tb, 'title') or ''
                    member['task_status'] = yaml_val(tb, 'status') or ''
                    break
        cast.append(member)
    return cast


PROGRESS = {
    'done': 100, 'complete': 100, 'merged': 100, 'approved': 100,
    'in_progress': 50, 'in_review': 80, 'review': 80,
    'assigned': 25, 'blocked': 25,
}

def load_tasks():
    d = BASE / 'queue' / 'tasks'
    if not d.exists():
        return []
    tasks = []
    for f in sorted(d.glob('*.yaml')):
        content = f.read_text(encoding='utf-8')
        for block in yaml_blocks(content, '- id:'):
            tid = yaml_val(block, 'id')
            if not tid:
                continue
            st = yaml_val(block, 'status') or 'pending'
            try:
                task_id = int(tid)
            except (ValueError, TypeError):
                continue
            tasks.append(dict(
                id=task_id, title=yaml_val(block, 'title') or '',
                status=st, branch=yaml_val(block, 'branch'),
                progress=PROGRESS.get(st, 0),
            ))
    tasks.sort(key=lambda t: t['id'])
    return tasks


def load_phases():
    path = BASE / 'dashboard.md'
    if not path.exists():
        return dict(current_phase=0, phases=[])
    content = path.read_text(encoding='utf-8')
    phases = []
    current = 0
    for line in content.split('\n'):
        m = re.match(
            r'-\s+(?:Phase\s+)?(\S+):\s+(\d+)/(\d+)\s+完了\s+\((\d+)%\)\s*(✅)?',
            line.strip())
        if not m:
            continue
        name = m.group(1)
        done, total, pct = int(m.group(2)), int(m.group(3)), int(m.group(4))
        complete = m.group(5) is not None
        num = int(name) if name.isdigit() else 99
        phases.append(dict(
            number=num,
            name=f'Phase {name}' if name.isdigit() else name,
            tasks_done=done, tasks_total=total,
            progress=pct,
            status='complete' if complete else 'active',
        ))
        if not complete:
            current = num
        elif num < 99 and num > current:
            current = num
    return dict(current_phase=current, phases=phases)


def load_production():
    path = BASE / 'config' / 'production.yaml'
    if not path.exists():
        return dict(movie_title='Unknown', project_name='Unknown')
    content = path.read_text(encoding='utf-8')
    movie_title = project_name = None
    section = None
    for line in content.split('\n'):
        if line.startswith('movie:'):
            section = 'movie'
        elif line.startswith('project:'):
            section = 'project'
        elif line and not line[0].isspace():
            section = None
        stripped = line.strip()
        if section == 'movie' and stripped.startswith('title:'):
            movie_title = stripped.split(':', 1)[1].strip().strip('"').strip("'")
        if section == 'project' and stripped.startswith('name:'):
            project_name = stripped.split(':', 1)[1].strip().strip('"').strip("'")
    return dict(
        movie_title=movie_title or 'Unknown Production',
        project_name=project_name or 'Unknown',
    )

def load_branches():
    """Build branch tree from dashboard.md task table + phase info."""
    path = BASE / 'dashboard.md'
    if not path.exists():
        return dict(branches=[])
    content = path.read_text(encoding='utf-8')

    # Parse completed tasks from "本日の戦果" table
    branches = []
    for m in re.finditer(
        r'\|\s*[\d:]+\s*\|\s*(\w+)\s*\|\s*#(\d+)\s+(.+?)\s*\|\s*完了\s*\|\s*(.*?)\s*\|',
        content
    ):
        slug, tid, title = m.group(1), int(m.group(2)), m.group(3).strip()
        review = m.group(4).strip()
        branches.append(dict(
            task_id=tid, slug=slug, title=title,
            status='merged' if 'approved' in review else 'complete',
            color=CAST_COLORS.get(slug, '#888'),
        ))

    # Assign phases using cumulative task counts
    phases = load_phases()['phases']
    idx, phase_num = 0, 1
    for p in phases:
        phase_num = p['number']
        for _ in range(p['tasks_total']):
            if idx < len(branches):
                branches[idx]['phase'] = phase_num
                idx += 1

    # Also add current active tasks (from YAML files, not yet in dashboard)
    done_ids = {b['task_id'] for b in branches}
    last_phase = phase_num
    tasks_dir = BASE / 'queue' / 'tasks'
    if tasks_dir.exists():
        for f in tasks_dir.glob('*.yaml'):
            try:
                tc = f.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError) as ex:
                print(f'[WARN] skipping {f.name}: {ex}', file=sys.stderr)
                continue
            for block in yaml_blocks(tc, '- id:'):
                tid = yaml_val(block, 'id')
                if not tid:
                    continue
                try:
                    tid = int(tid)
                except (ValueError, TypeError):
                    continue
                if tid in done_ids:
                    continue
                st = yaml_val(block, 'status') or 'pending'
                slug = f.stem
                branches.append(dict(
                    task_id=tid, slug=slug,
                    title=yaml_val(block, 'title') or '',
                    status=st,
                    color=CAST_COLORS.get(slug, '#888'),
                    phase=last_phase,
                ))

    branches.sort(key=lambda b: b['task_id'])
    return dict(branches=branches)


def load_episodes():
    """Load episode list from episodes/*.yaml and determine status."""
    episodes_dir = BASE / 'episodes'
    production = load_production()
    prod_title = production.get('movie_title', 'Unknown Production')

    # Determine current phase from dashboard for "recording" status
    phase_data = load_phases()
    current_phase = phase_data.get('current_phase', 0)

    episodes = []
    if episodes_dir.exists():
        for f in sorted(episodes_dir.glob('ep*.yaml')):
            m = re.match(r'ep(\d+)\.yaml$', f.name)
            if not m:
                continue
            ep_num = int(m.group(1))
            try:
                content = f.read_text(encoding='utf-8').strip()
            except (OSError, UnicodeDecodeError):
                content = ''

            if content:
                parsed = parse_episode_yaml(content)
                episodes.append(dict(
                    number=ep_num,
                    title=parsed.get('title'),
                    synopsis=parsed.get('synopsis'),
                    scene_count=len(parsed.get('scenes', [])),
                    status='available',
                ))
            else:
                episodes.append(dict(
                    number=ep_num,
                    title=None,
                    synopsis=None,
                    scene_count=0,
                    status='recording',
                ))

    # Episodes for phases beyond current are "recording" even if file exists
    # (current_phase is the highest active/completed phase number)
    for ep in episodes:
        if ep['number'] > current_phase and ep['status'] == 'available':
            # Only mark as recording if it has no real content
            pass  # file has content, keep available

    episodes.sort(key=lambda e: e['number'])
    return dict(production=prod_title, episodes=episodes)


def load_episode(n):
    """Load a single episode by number. Returns dict or None if not found."""
    ep_path = BASE / 'episodes' / f'ep{n}.yaml'
    if not ep_path.exists():
        return None
    try:
        content = ep_path.read_text(encoding='utf-8').strip()
    except (OSError, UnicodeDecodeError):
        return None
    if not content:
        return None
    return parse_episode_yaml(content)


def send_to_producer(msg):
    """Send a message to the Producer pane via wake-agent.sh."""
    panes = BASE / 'config' / 'panes.yaml'
    if not panes.exists():
        return dict(ok=False, error='panes.yaml not found')
    pane_id = yaml_val(panes.read_text(encoding='utf-8'), 'producer')
    if not pane_id:
        return dict(ok=False, error='producer pane not configured')
    # Sanitize: strip control chars, limit length
    msg = re.sub(r'[\x00-\x1f\x7f]', '', msg)[:500]
    if not msg:
        return dict(ok=False, error='empty after sanitization')
    # Use wake-agent.sh per CLAUDE.md Section 3
    helper = BASE / 'scripts' / 'wake-agent.sh'
    if not helper.exists():
        return dict(ok=False, error='wake-agent.sh not found')
    try:
        subprocess.run(['bash', str(helper), pane_id, msg],
                       check=True, timeout=10)
        return dict(ok=True, error=None)
    except FileNotFoundError:
        return dict(ok=False, error='bash/tmux not available')
    except subprocess.CalledProcessError as ex:
        print(f'[WARN] send_to_producer failed: {ex}', file=sys.stderr)
        return dict(ok=False, error='tmux command failed')
    except subprocess.TimeoutExpired:
        print('[WARN] send_to_producer timed out', file=sys.stderr)
        return dict(ok=False, error='tmux timeout')


# ---------------------------------------------------------------------------
# HTTP Handler
# ---------------------------------------------------------------------------

class Handler(http.server.BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        pass  # suppress access log

    def _json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = urlparse(self.path)
        path = p.path
        q = parse_qs(p.query)

        if path == '/':
            self._serve_file('control-room.html')
        elif path == '/theater':
            self._serve_file('theater.html')
        elif path == '/api/activity':
            lim = min(int(q.get('limit', ['50'])[0]), 500)
            self._json(dict(entries=load_activity(lim)))
        elif path == '/api/cast' or path == '/api/roster':
            try:
                result = load_cast()
            except Exception as ex:
                print(f'[ERROR] load_cast: {ex}', file=sys.stderr)
                self._json(dict(error='internal error', cast=[]), 500)
                return
            self._json(dict(cast=result))
        elif path == '/api/tasks':
            self._json(dict(tasks=load_tasks()))
        elif path == '/api/phases' or path == '/api/dashboard':
            self._json(load_phases())
        elif path == '/api/production':
            self._json(load_production())
        elif path == '/api/branches':
            try:
                result = load_branches()
            except Exception as ex:
                print(f'[ERROR] load_branches: {ex}', file=sys.stderr)
                self._json(dict(error='internal error', branches=[]), 500)
                return
            self._json(result)
        elif path == '/api/episodes':
            try:
                result = load_episodes()
            except Exception as ex:
                print(f'[ERROR] load_episodes: {ex}', file=sys.stderr)
                self._json(dict(error='internal error', production='', episodes=[]), 500)
                return
            self._json(result)
        elif (ep_match := re.match(r'^/api/episodes/(\d{1,4})$', path)):
            ep_num = int(ep_match.group(1))
            try:
                result = load_episode(ep_num)
            except Exception as ex:
                print(f'[ERROR] load_episode({ep_num}): {ex}', file=sys.stderr)
                self._json(dict(error='internal error'), 500)
                return
            if result is None:
                self._json(dict(error=f'Episode {ep_num} not found'), 404)
            else:
                self._json(result)
        elif path == '/api/events':
            self._sse()
        elif path == '/api/health':
            self._json(dict(ok=True))
        else:
            self.send_error(404)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_POST(self):
        p = urlparse(self.path).path
        if p == '/api/message':
            try:
                length = int(self.headers.get('Content-Length', 0))
                if length <= 0 or length > 10000:
                    self._json(dict(success=False, error='invalid request'), 400)
                    return
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict):
                    self._json(dict(success=False, error='invalid JSON'), 400)
                    return
            except (ValueError, json.JSONDecodeError):
                self._json(dict(success=False, error='invalid JSON'), 400)
                return
            msg = body.get('message', '').strip()
            if not msg:
                self._json(dict(success=False, error='empty message'), 400)
                return
            result = send_to_producer(msg)
            self._json(dict(success=result['ok'], error=result['error']),
                       200 if result['ok'] else 502)
        else:
            self.send_error(404)

    def _serve_file(self, filename):
        hp = (BASE / 'ui' / filename).resolve()
        ui_dir = (BASE / 'ui').resolve()
        if not str(hp).startswith(str(ui_dir)):
            self.send_error(403)
            return
        if not hp.exists():
            self.send_error(404, f'{filename} not found')
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.wfile.write(hp.read_bytes())

    def _sse(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()

        log_path = BASE / 'logs' / 'activity.log'
        dashboard_path = BASE / 'dashboard.md'
        roster_path = BASE / 'cast' / 'roster.yaml'

        last_size = log_path.stat().st_size if log_path.exists() else 0
        dashboard_mtime = dashboard_path.stat().st_mtime if dashboard_path.exists() else 0
        roster_mtime = roster_path.stat().st_mtime if roster_path.exists() else 0
        tick = 0
        try:
            while True:
                # Activity log changes (existing)
                if log_path.exists():
                    sz = log_path.stat().st_size
                    if sz > last_size:
                        with open(log_path, 'r', encoding='utf-8') as f:
                            f.seek(last_size)
                            for line in f.read().strip().split('\n'):
                                entry = parse_activity_line(line)
                                if entry:
                                    d = json.dumps(entry, ensure_ascii=False)
                                    self.wfile.write(
                                        f'event: activity\ndata: {d}\n\n'
                                        .encode('utf-8'))
                                    self.wfile.flush()
                        last_size = sz
                    elif sz < last_size:
                        last_size = sz  # file truncated

                # Dashboard changes (new)
                if dashboard_path.exists():
                    mt = dashboard_path.stat().st_mtime
                    if mt > dashboard_mtime:
                        dashboard_mtime = mt
                        try:
                            phases = load_phases()
                            d = json.dumps(phases, ensure_ascii=False)
                            self.wfile.write(
                                f'event: dashboard\ndata: {d}\n\n'
                                .encode('utf-8'))
                            self.wfile.flush()
                        except Exception as ex:
                            print(f'[WARN] SSE dashboard: {ex}',
                                  file=sys.stderr)

                # Roster changes (new)
                if roster_path.exists():
                    mt = roster_path.stat().st_mtime
                    if mt > roster_mtime:
                        roster_mtime = mt
                        try:
                            cast = load_cast()
                            d = json.dumps(dict(cast=cast),
                                           ensure_ascii=False)
                            self.wfile.write(
                                f'event: roster\ndata: {d}\n\n'
                                .encode('utf-8'))
                            self.wfile.flush()
                        except Exception as ex:
                            print(f'[WARN] SSE roster: {ex}',
                                  file=sys.stderr)

                tick += 1
                if tick >= 15:
                    self.wfile.write(b': heartbeat\n\n')
                    self.wfile.flush()
                    tick = 0
                time.sleep(1)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    # Ensure UTF-8 output on Windows
    if sys.stdout.encoding != 'utf-8':
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    if sys.stderr.encoding != 'utf-8':
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')

    # CLI args
    args = sys.argv[1:]
    for i, a in enumerate(args):
        if a == '--port' and i + 1 < len(args):
            PORT = int(args[i + 1])
        if a == '--base' and i + 1 < len(args):
            BASE = Path(args[i + 1])

    server = http.server.ThreadingHTTPServer(('127.0.0.1', PORT), Handler)
    print(f'ENSEMBLE CAST -- Theater Server')
    print(f'  http://localhost:{PORT}')
    print(f'  Base: {BASE}')
    print(f'  Ctrl+C to stop\n')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nTheater closed.')
        server.shutdown()
