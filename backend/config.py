"""Small .env loader, without shell evaluation or exposing values."""
import os


def load_env(path):
    if not path.exists(): return
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        line=line.strip()
        if not line or line.startswith('#') or '=' not in line: continue
        key,value=line.split('=',1)
        key,value=key.strip(),value.strip()
        if not key.replace('_','').isalnum(): continue
        if len(value)>=2 and value[0]==value[-1] and value[0] in ('"',"'"): value=value[1:-1]
        os.environ.setdefault(key,value)
