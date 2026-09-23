"""Cross-platform local launcher: python run.py (Python 3.11+ and Flutter required)."""
import argparse
import hashlib
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import venv

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description='Build and serve Career Quest locally')
    parser.add_argument('--port', type=int, default=8000)
    parser.add_argument('--skip-build', action='store_true', help='Reuse an existing Flutter web build')
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error('Port must be between 1 and 65535')
    with socket.socket() as probe:
        try:
            probe.bind(('127.0.0.1', args.port))
        except OSError:
            parser.error(f'Port {args.port} is busy; choose another with --port')
    env = ROOT / '.venv'
    python = env / ('Scripts/python.exe' if sys.platform == 'win32' else 'bin/python')
    if not python.exists():
        print('Creating Python environment...', flush=True)
        venv.create(env, with_pip=True)
    requirements = ROOT / 'requirements.lock'
    marker = env / '.requirements-installed'
    digest = hashlib.sha256(requirements.read_bytes()).hexdigest()
    if not marker.exists() or marker.read_text() != digest:
        subprocess.run([str(python), '-m', 'pip', 'install', '-r', str(requirements)], check=True, cwd=ROOT)
        marker.write_text(digest)
    if not args.skip_build:
        flutter = shutil.which('flutter')
        if flutter is None:
            parser.error('Flutter is not on PATH. Install Flutter and reopen the terminal.')
        subprocess.run([flutter, 'pub', 'get'], check=True, cwd=ROOT / 'frontend')
        subprocess.run([flutter, 'build', 'web'], check=True, cwd=ROOT / 'frontend')
    if not (ROOT / 'frontend/build/web/index.html').exists():
        parser.error('No web build found. Run without --skip-build first.')
    print(f'Career Quest: http://127.0.0.1:{args.port}\nAPI docs: http://127.0.0.1:{args.port}/docs', flush=True)
    try:
        return subprocess.call([str(python), '-m', 'uvicorn', 'backend.main:app',
                                '--host', '127.0.0.1', '--port', str(args.port)], cwd=ROOT)
    except KeyboardInterrupt:
        return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as exc:
        print(f'Command failed (exit {exc.returncode}). See the output above.', file=sys.stderr)
        sys.exit(exc.returncode)
