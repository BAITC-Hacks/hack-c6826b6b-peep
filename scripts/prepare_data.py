"""Copy only the four known dataset files from the supplied ZIP; never execute attachments."""
import argparse
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent
NAMES = {'employees.json', 'events.json', 'skills.json', 'activity_history.csv'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    args = parser.parse_args()
    files = {}
    with ZipFile(args.archive) as archive:
        for entry in archive.infolist():
            if '__MACOSX' in entry.filename or entry.is_dir():
                continue
            name = Path(entry.filename).name
            if name not in NAMES:
                continue
            if entry.file_size > 12 * 1024 * 1024 or name in files:
                parser.error('Duplicate or oversized dataset file')
            files[name] = archive.read(entry)
    if files.keys() != NAMES:
        parser.error('Archive must contain employees.json, events.json, skills.json, activity_history.csv')
    target = ROOT / 'data/sample'
    # Do not silently replace any local modifications.
    for name, content in files.items():
        path = target / name
        if path.exists() and path.read_bytes() != content:
            parser.error(f'{path} already exists with different contents')
    target.mkdir(parents=True, exist_ok=True)
    for name, content in files.items():
        (target / name).write_bytes(content)
    print(f'Prepared {len(files)} local files in {target}')


if __name__ == '__main__':
    main()
