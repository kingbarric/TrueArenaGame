import importlib.util
import io
import os
import stat
import pathlib
import tarfile
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('release_bundle', pathlib.Path(__file__).parents[1] / 'infra/release_bundle.py')
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)
SHA = 'a' * 40


class ReleaseBundleTest(unittest.TestCase):
    def archive(self, directory, extra=None, revision=SHA):
        path = pathlib.Path(directory) / 'release.tar.gz'
        jar = io.BytesIO()
        with zipfile.ZipFile(jar, 'w') as z:
            z.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0')
        content = {name: b'public configuration' for name in bundle.REQUIRED}
        content['revision.txt'] = revision.encode()
        content['backend.jar'] = jar.getvalue()
        content['website/.well-known/assetlinks.json'] = b'[]'
        with tarfile.open(path, 'w:gz') as archive:
            for name, data in content.items():
                member = tarfile.TarInfo(name); member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
            if extra:
                archive.addfile(extra, io.BytesIO(b'x' * extra.size))
        return path

    def test_valid_release_and_well_known_files(self):
        with tempfile.TemporaryDirectory() as d:
            target = pathlib.Path(d) / 'stage'
            old_mask = os.umask(0o077)
            try:
                bundle.unpack(self.archive(d), target, SHA)
            finally:
                os.umask(old_mask)
            self.assertEqual(stat.S_IMODE((target / 'backend.jar').stat().st_mode), 0o644)
            self.assertTrue((target / 'backend.jar').is_file())
            self.assertEqual((target / 'revision.txt').read_text(), SHA)

    def test_traversal_secrets_symlinks_and_duplicates_are_rejected_before_writing(self):
        for name, kind in [('../outside', tarfile.REGTYPE), ('infra/.env', tarfile.REGTYPE),
                           ('website/.env', tarfile.REGTYPE), ('website/link', tarfile.SYMTYPE),
                           ('backend.jar', tarfile.REGTYPE)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as d:
                extra = tarfile.TarInfo(name);extra.type=kind;extra.linkname='/etc/passwd';extra.size=0
                target=pathlib.Path(d)/'stage'
                with self.assertRaises(ValueError): bundle.unpack(self.archive(d,extra),target,SHA)
                self.assertFalse(target.exists())

    def test_wrong_commit_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError, 'revision mismatch'):
                bundle.unpack(self.archive(d,revision='b'*40),pathlib.Path(d)/'stage',SHA)


if __name__ == '__main__':
    unittest.main()
