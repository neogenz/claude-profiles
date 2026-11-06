import importlib.util
import json
from pathlib import Path
from unittest.mock import patch
import tempfile
import subprocess

spec = importlib.util.spec_from_file_location('profiles', Path(__file__).resolve().parents[1] / 'src/claude-profiles.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
temporary = tempfile.TemporaryDirectory(prefix='profiles-check-')
home = Path(temporary.name)
app = home / 'Claude.app'
app.mkdir()
source = home / '.claude'
source.mkdir()
(source / 'settings.json').write_text(json.dumps({'env': {'ANTHROPIC_API_KEY': 'private', 'ANTHROPIC_CUSTOM_HEADERS': 'Authorization: Bearer synthetic-test-value', 'SAFE_SETTING': 'yes'}, 'apiKeyHelper': 'secret', 'enabledPlugins': {'personal': True}}))
(source / 'settings.local.json').write_text(json.dumps({'env': {'CLAUDE_CODE_OAUTH_TOKEN': 'private', 'LOCAL_SETTING': 'yes'}, 'apiKeyHelper': 'secret', 'hooks': {'SessionStart': []}}))
(source / 'CLAUDE.md').write_text('instructions')
(source / 'output-styles').mkdir()
(source / 'output-styles/concise.md').write_text('style')
(home / '.claude.json').write_text(json.dumps({'oauthAccount': {'email': 'personal'}, 'mcpServers': {'example': {'command': 'example'}}}))
original = {f: f.read_bytes() for f in home.rglob('*') if f.is_file()}
with patch.object(Path, 'home', return_value=home), patch.object(p, 'ROOT', home / 'Library/Application Support/Claude-Profile-Launcher'), patch.object(p, 'APP', app):
    for index, path in enumerate((source / 'settings.json', source / 'settings.local.json', home / '.claude.json')):
        before = path.read_bytes()
        try:
            path.write_text('{broken')
            try:
                p.install('broken-' + str(index))
            except json.JSONDecodeError:
                pass
            else:
                raise AssertionError('Malformed source should prevent profile creation')
            assert all(not target.exists() for target in p.paths('broken-' + str(index)))
            assert not (home / f'Applications/Claude Profiles/Claude BROKEN-{index}.app').exists()
        finally:
            path.write_bytes(before)
    p.install('cla')
    p.install('third')
    launcher = home / 'Applications/Claude Profiles/Claude CLA.app/Contents/MacOS/launch'
    assert str(p.ROOT / 'python') in launcher.read_text()
    assert p.sys.executable not in launcher.read_text()
    code, data = p.paths('cla')
    settings = json.loads((code / 'settings.json').read_text())
    assert settings['env'] == {'SAFE_SETTING': 'yes'}
    assert 'apiKeyHelper' not in settings and 'enabledPlugins' not in settings
    local = json.loads((code / 'settings.local.json').read_text())
    assert local['env'] == {'LOCAL_SETTING': 'yes'}
    assert 'apiKeyHelper' not in local
    assert local['hooks'] == {'SessionStart': []}
    assert (code / 'output-styles/concise.md').read_text() == 'style'
    assert not (code / 'CLAUDE.md').exists()
    (code / 'CLAUDE.md').write_text('outdated instructions')
    p.sync(code)
    assert not (code / 'CLAUDE.md').exists(), 'A copy left by an earlier sync should be removed, even if outdated'
    assert 'oauthAccount' not in json.loads((code / '.claude.json').read_text())
    settings['enabledPlugins'] = {'cla-only': True}
    (code / 'settings.json').write_text(json.dumps(settings))
    mixed = json.loads((code / '.claude.json').read_text())
    mixed['oauthAccount'] = {'email': 'cla'}
    (code / '.claude.json').write_text(json.dumps(mixed))
    p.sync(code)
    assert json.loads((code / 'settings.json').read_text())['enabledPlugins'] == {'cla-only': True}
    assert json.loads((code / '.claude.json').read_text())['oauthAccount'] == {'email': 'cla'}
    with patch.object(p.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, f'111 {p.APP}/Contents/MacOS/Claude\n123 {p.APP}/Contents/MacOS/Claude --user-data-dir={data}-other\n456 {p.APP}/Contents/MacOS/Claude --user-data-dir={data}\n')):
        assert p.processes(data) == [456]
        assert p.processes(None) == [111]
        profiles = p.profiles()
        assert [profile['id'] for profile in profiles] == ['__personal__', 'cla', 'third']
        assert [profile['pid'] for profile in profiles] == [111, 456, None]
        assert [profile['managed'] for profile in profiles] == [False, True, True]
        assert profiles[0]['code'] == str(source)
        assert profiles[1]['code'] == str(code) and profiles[1]['data'] == str(data)
        assert profiles[1]['shared'] is True
    with patch.object(p, 'processes', side_effect=[[], [456]]), patch.object(p.subprocess, 'run') as run:
        p.launch('cla')
        argv = run.call_args.args[0]
        assert 'CLAUDE_CONFIG_DIR=' + str(code) in argv
        assert 'CLAUDE_USER_DATA_DIR=' + str(data) in argv
    p.configure('cla', False)
    settings = json.loads((code / 'settings.json').read_text())
    settings['env']['SAFE_SETTING'] = 'profile-specific'
    (code / 'settings.json').write_text(json.dumps(settings))
    independent = (code / 'settings.json').read_bytes()
    with patch.object(p, 'processes', side_effect=[[], [456]]), patch.object(p.subprocess, 'run'):
        p.launch('cla')
    assert (code / 'settings.json').read_bytes() == independent
    with patch.object(p, 'processes', return_value=[]):
        assert p.profiles()[1]['shared'] is False
    p.configure('cla', True)
    assert (code / 'settings.json').read_bytes() == independent
    with patch.object(p, 'processes', side_effect=[[], [456]]), patch.object(p.subprocess, 'run'):
        p.launch('cla')
    settings = json.loads((code / 'settings.json').read_text())
    assert settings['env']['SAFE_SETTING'] == 'yes'
    assert settings['enabledPlugins'] == {'cla-only': True}
    assert json.loads((code / '.claude.json').read_text())['oauthAccount'] == {'email': 'cla'}
    with patch.object(p.sys, 'argv', ['profiles', 'sync', 'cla']), patch.object(p, 'processes', return_value=[456]), patch.object(p, 'sync') as synchronize:
        assert p.main() == 1
        synchronize.assert_not_called()
    assert all(f.read_bytes() == before for f, before in original.items())
print('PASS: malformed-source preflight, profile inventory, auth/plugin isolation, independent/shared launch behavior, active sync refusal, exact process match, launch environment, original unchanged')
