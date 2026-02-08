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
                    member['task_id'] = int(tid)
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
            tasks.append(dict(
                id=int(tid), title=yaml_val(block, 'title') or '',
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
    tasks_dir = BASE / 'queue' / 'tasks'
    if tasks_dir.exists():
        for f in tasks_dir.glob('*.yaml'):
            tc = f.read_text(encoding='utf-8')
            for block in yaml_blocks(tc, '- id:'):
                tid = yaml_val(block, 'id')
                if not tid:
                    continue
                tid = int(tid)
                if tid in done_ids:
                    continue
                st = yaml_val(block, 'status') or 'pending'
                slug = f.stem
                branches.append(dict(
                    task_id=tid, slug=slug,
                    title=yaml_val(block, 'title') or '',
                    status=st,
                    color=CAST_COLORS.get(slug, '#888'),
                    phase=phase_num,
                ))

    branches.sort(key=lambda b: b['task_id'])
    return dict(branches=branches)


def send_to_producer(msg):
    """Send a message to the Producer pane via tmux."""
    panes = BASE / 'config' / 'panes.yaml'
    if not panes.exists():
        return False
    pane_id = yaml_val(panes.read_text(encoding='utf-8'), 'producer')
    if not pane_id:
        return False
    try:
        subprocess.run(['tmux', 'send-keys', '-t', pane_id, msg],
                       check=True, timeout=5)
        subprocess.run(['tmux', 'send-keys', '-t', pane_id, 'Enter'],
                       check=True, timeout=5)
        return True
    except (FileNotFoundError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired):
        return False


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
            self._serve_html()
        elif path == '/api/activity':
            lim = int(q.get('limit', ['50'])[0])
            self._json(dict(entries=load_activity(lim)))
        elif path == '/api/cast':
            try:
                result = load_cast()
            except Exception as ex:
                self._json(dict(error=str(ex), cast=[]), 500)
                return
            self._json(dict(cast=result))
        elif path == '/api/tasks':
            self._json(dict(tasks=load_tasks()))
        elif path == '/api/phases':
            self._json(load_phases())
        elif path == '/api/production':
            self._json(load_production())
        elif path == '/api/branches':
            self._json(load_branches())
        elif path == '/api/events':
            self._sse()
        elif path == '/api/health':
            self._json(dict(ok=True))
        else:
            self.send_error(404)

    def do_POST(self):
        p = urlparse(self.path).path
        if p == '/api/message':
            length = int(self.headers.get('Content-Length', 0))
            body = json.loads(self.rfile.read(length)) if length else {}
            msg = body.get('message', '').strip()
            if not msg:
                self._json(dict(success=False, error='empty message'), 400)
                return
            ok = send_to_producer(msg)
            self._json(dict(success=ok,
                            error=None if ok else 'tmux not available'))
        else:
            self.send_error(404)

    def _serve_html(self):
        hp = BASE / 'ui' / 'theater.html'
        if not hp.exists():
            self.send_error(404, 'theater.html not found')
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
        last_size = log_path.stat().st_size if log_path.exists() else 0
        tick = 0
        try:
            while True:
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

    server = http.server.ThreadingHTTPServer(('', PORT), Handler)
    print(f'ENSEMBLE CAST -- Theater Server')
    print(f'  http://localhost:{PORT}')
    print(f'  Base: {BASE}')
    print(f'  Ctrl+C to stop\n')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nTheater closed.')
        server.shutdown()
