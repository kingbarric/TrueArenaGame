"""Extract chosen MakeHuman garment folders from downloaded asset-pack zips.

Usage: python3 -I scripts/extract-packs.py <downloads dir> <source root> <folder> ...

Packs come from https://static.makehumancommunity.org/assets/assetpacks.html
(see docs/SLAYHUUD_ASSET_CREDITS.md). Only `clothes/<folder>/` entries are
written, under <source root>/clothes/<folder>; archive paths that would escape
that folder are refused. Nothing from the archives is executed.
"""
import pathlib
import sys
import zipfile

downloads, root, *folders = sys.argv[1:]
wanted = set(folders)
target = pathlib.Path(root, 'clothes').resolve()
found = set()
for archive in sorted(pathlib.Path(downloads).glob('*.zip')):
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            parts = pathlib.PurePosixPath(info.filename).parts
            if info.is_dir() or 'clothes' not in parts:
                continue
            rest = parts[parts.index('clothes') + 1:]
            if len(rest) < 2 or rest[0] not in wanted:
                continue
            if (target / rest[0]).is_symlink():
                found.add(rest[0])  # already provided by a linked source folder
                continue
            out = (target / pathlib.Path(*rest)).resolve()
            if target not in out.parents:
                raise SystemExit(f'refusing unsafe path {info.filename} in {archive.name}')
            out.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as src:
                out.write_bytes(src.read())
            found.add(rest[0])
missing = wanted - found
print(f'extracted {len(found)} garments' + (f'; missing: {sorted(missing)}' if missing else ''))
sys.exit(1 if missing else 0)
