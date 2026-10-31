#!/usr/bin/env python3
"""Build and install the local profile manager, without copying account data."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parent
BUNDLE_ID = 'local.claudeprofiles.manager'


def build():
    if sys.platform != 'darwin':
        raise RuntimeError('The native manager requires macOS.')
    if sys.version_info < (3, 9):
        raise RuntimeError('Python 3.9 or newer is required.')
    swift = subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip()
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    build_dir = REPO / 'build'
    build_dir.mkdir(exist_ok=True)
    app = build_dir / 'Profils Claude.app'
    contents = app / 'Contents'
    (contents / 'MacOS').mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(build_dir / 'module-cache'))
    architecture = os.uname().machine
    subprocess.run([swift, '-sdk', sdk, '-parse-as-library', '-O', '-target',
                    architecture + '-apple-macosx14.0',
                    str(REPO / 'src/ClaudeProfiles.swift'), '-o',
                    str(contents / 'MacOS/ProfilsClaude')], env=env, check=True)
    (contents / 'Resources').mkdir(exist_ok=True)
    shutil.copyfile(REPO / 'assets/AppIcon.icns', contents / 'Resources/AppIcon.icns')
    (contents / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleName': 'Profils Claude', 'CFBundleDisplayName': 'Profils Claude',
        'CFBundleIdentifier': BUNDLE_ID, 'CFBundleExecutable': 'ProfilsClaude',
        'CFBundlePackageType': 'APPL', 'CFBundleVersion': '2',
        'CFBundleIconFile': 'AppIcon.icns',
        'CFBundleShortVersionString': '1.1', 'NSHighResolutionCapable': True,
        'LSMinimumSystemVersion': '14.0',
    }))
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    return app


def install(app):
    home = Path.home()
    root = home / 'Library/Application Support/Claude-Profile-Launcher'
    destination = home / 'Applications/Claude Profiles/Profils Claude.app'
    if root.is_symlink() or destination.is_symlink():
        raise ValueError('Refusing to replace a linked installation directory.')
    if destination.exists():
        info = plistlib.loads((destination / 'Contents/Info.plist').read_bytes())
        if info.get('CFBundleIdentifier') != BUNDLE_ID:
            raise ValueError('Another application already uses the destination path.')
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Stage complete replacements first; retain the previous manager for rollback.
    with tempfile.TemporaryDirectory(prefix='install-', dir=root) as temporary:
        stage = Path(temporary)
        shutil.copytree(app, stage / 'Profils Claude.app')
        shutil.copyfile(REPO / 'src/claude-profiles.py', stage / 'claude-profiles.py')
        (stage / 'python').symlink_to(Path(sys.executable).resolve())
        if destination.exists():
            backup = root / 'previous-installations'
            backup.mkdir(exist_ok=True)
            previous = Path(tempfile.mkdtemp(prefix='manager-', dir=backup))
            destination.rename(previous / destination.name)
        (stage / 'Profils Claude.app').rename(destination)
        for name in ('claude-profiles.py', 'python'):
            (stage / name).replace(root / name)
    print('Installed:', destination)
    print('Python runtime:', Path(sys.executable).resolve())
    print('Existing profile data and Claude.app were not modified.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-only', action='store_true', help='Build without installing anything in your home directory.')
    args = parser.parse_args()
    try:
        app = build()
        if args.build_only:
            print('Built:', app)
        else:
            install(app)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print('ERROR:', error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
