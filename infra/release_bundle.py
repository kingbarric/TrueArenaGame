#!/usr/bin/env python3
"""Build and validate the limited production deployment archive."""
import argparse
import pathlib
import subprocess
import tarfile
import zipfile

RUNTIME_FILES = {
    'backend.jar': 'backend/ta-app/target/truearena-backend.jar',
    'Dockerfile.runtime': 'backend/Dockerfile.runtime',
    'stockfish/install.sh': 'backend/stockfish/install.sh',
    'scan/install.sh': 'backend/scan/install.sh',
}
REQUIRED = set(RUNTIME_FILES) | {'revision.txt',
            'infra/docker-compose.prod.yml', 'infra/Caddyfile.prod',
            'infra/livekit.prod.yaml', 'infra/smoke.sh'}
MAX_SIZE = 512 * 1024 * 1024


def allowed(name):
    p = pathlib.PurePosixPath(name)
    return (not p.is_absolute() and '..' not in p.parts and
            (name in REQUIRED or (name.startswith('website/') and
             not any(part.startswith('.') and part != '.well-known' for part in p.parts))))


def pack(root, output, revision):
    root = pathlib.Path(root)
    website = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z', 'website'], text=True).split('\0')
    files = {name: root / name for name in REQUIRED - {'backend.jar', 'revision.txt'}}
    files.update({name: root / source for name, source in RUNTIME_FILES.items()})
    files.update({name: root / name for name in website if name})
    with tarfile.open(output, 'w:gz') as archive:
        import io
        content = (revision + '\n').encode()
        info = tarfile.TarInfo('revision.txt')
        info.size = len(content)
        archive.addfile(info, io.BytesIO(content))
        for name, path in sorted(files.items()):
            if not allowed(name) or not path.is_file() or path.is_symlink():
                raise ValueError('Invalid release file: ' + name)
            archive.add(path, arcname=name, recursive=False)


def unpack(archive_path, destination, revision):
    destination = pathlib.Path(destination)
    if destination.exists() and any(destination.iterdir()):
        raise ValueError('Release staging directory must be empty')
    with tarfile.open(archive_path, 'r:gz') as archive:
        members = archive.getmembers()
        names = [m.name for m in members]
        if len(members) > 2000 or len(names) != len(set(names)) or sum(m.size for m in members) > MAX_SIZE:
            raise ValueError('Oversized or duplicate release members')
        if not REQUIRED.issubset(names):
            raise ValueError('Incomplete release archive')
        for m in members:
            if not m.isfile() or not allowed(m.name):
                raise ValueError('Unexpected release member: ' + m.name)
        # Validate every path before writing any archive contents.
        for m in members:
            path = destination / m.name
            path.parent.mkdir(parents=True, exist_ok=True)
            with archive.extractfile(m) as source, path.open('wb') as target:
                import shutil
                shutil.copyfileobj(source, target)
            path.chmod(0o644)
        if (destination / 'revision.txt').read_text().strip() != revision:
            raise ValueError('Release revision mismatch')
        with zipfile.ZipFile(destination / 'backend.jar') as jar:
            if 'META-INF/MANIFEST.MF' not in jar.namelist() or jar.testzip() is not None:
                raise ValueError('Invalid backend artifact')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=['pack', 'unpack'])
    parser.add_argument('path')
    parser.add_argument('destination')
    parser.add_argument('revision')
    args = parser.parse_args()
    if len(args.revision) != 40 or any(c not in '0123456789abcdef' for c in args.revision):
        parser.error('Expected a full commit SHA')
    (pack if args.operation == 'pack' else unpack)(args.path, args.destination, args.revision)
