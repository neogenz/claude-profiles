"""Exercise installation in a temporary home; never compile or modify real profiles."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[1] / 'install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

with tempfile.TemporaryDirectory(prefix='profile-install-check-') as temporary:
    home = Path(temporary)
    built = home / 'built.app'
    (built / 'Contents/MacOS').mkdir(parents=True)
    (built / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': installer.BUNDLE_ID}))
    (built / 'Contents/MacOS/ProfilsClaude').write_text('version one')
    profile = home / '.claude-existing'
    profile.mkdir()
    (profile / 'settings.json').write_text('{"custom":true}')
    with patch.object(Path, 'home', return_value=home):
        installer.install(built)
        target = home / 'Applications/Claude Profiles/Profils Claude.app'
        runtime = home / 'Library/Application Support/Claude-Profile-Launcher'
        assert (target / 'Contents/MacOS/ProfilsClaude').read_text() == 'version one'
        assert (runtime / 'python').resolve() == Path(installer.sys.executable).resolve()
        assert (runtime / 'claude-profiles.py').read_bytes() == (installer.REPO / 'src/claude-profiles.py').read_bytes()
        (built / 'Contents/MacOS/ProfilsClaude').write_text('version two')
        installer.install(built)
        assert (target / 'Contents/MacOS/ProfilsClaude').read_text() == 'version two'
        backups = list((runtime / 'previous-installations').glob('manager-*/Profils Claude.app/Contents/MacOS/ProfilsClaude'))
        assert len(backups) == 1 and backups[0].read_text() == 'version one'
        assert (profile / 'settings.json').read_text() == '{"custom":true}'
        (target / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'unrelated.application'}))
        try:
            installer.install(built)
        except ValueError:
            pass
        else:
            raise AssertionError('Unrelated application must not be overwritten')
        assert plistlib.loads((target / 'Contents/Info.plist').read_bytes())['CFBundleIdentifier'] == 'unrelated.application'
print('PASS: install, upgrade backup, runtime selection, existing profiles unchanged, unrelated application protected')
