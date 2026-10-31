#!/usr/bin/env python3
"""Local Claude profile launcher. No changes to the original profile.
Usage: python3 claude-profiles.py install cla
       python3 claude-profiles.py launch cla
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

APP = Path('/Applications/Claude.app')
ROOT = Path.home() / 'Library/Application Support/Claude-Profile-Launcher'


def paths(name):
    if not re.fullmatch(r'[a-z][a-z0-9-]{0,30}', name):
        raise ValueError('Nom attendu : lettres minuscules, chiffres et tirets (ex. cla).')
    return Path.home()/('.claude-'+name), Path.home()/('Library/Application Support/claude-'+name)


def read_json(p):
    return json.loads(p.read_text()) if p.exists() else {}


def write_json(p, data):
    if p.is_symlink():
        raise ValueError('Refus de modifier un lien : '+str(p))
    tmp = p.with_name(p.name+'.profile-tmp')
    if tmp.exists() or tmp.is_symlink():
        raise ValueError('Fichier temporaire existant : '+str(tmp))
    with tmp.open('x') as f:
        os.chmod(tmp, 0o600)
        json.dump(data, f, indent=2, ensure_ascii=False)
    tmp.replace(p)


def processes(data):
    result = subprocess.run(['/bin/ps','-axo','pid=,command='],capture_output=True,text=True,check=True)
    found=[]
    for line in result.stdout.splitlines():
        fields=line.strip().split(None,1)
        if data is None and len(fields)==2 and fields[1]==str(APP/'Contents/MacOS/Claude'):
            found.append(int(fields[0]))
            continue
        if len(fields)==2 and fields[1].startswith(str(APP/'Contents/MacOS/Claude')+' ') and re.search(re.escape('--user-data-dir='+str(data))+r'(?:\s|$)',fields[1]):
            found.append(int(fields[0]))
    return found


def sync(code):
    source=Path.home()/'.claude'
    # Source is always read-only. Plugins and all runtime state remain profile-specific.
    for name in ('settings.json','settings.local.json'):
        if name=='settings.local.json' and not (source/name).exists():
            continue
        settings=read_json(source/name)
        local=read_json(code/name)
        for key in ('enabledPlugins','extraKnownMarketplaces'):
            settings.pop(key,None)
            if key in local:
                settings[key]=local[key]
        # Never propagate authentication environment variables or helpers.
        settings.pop('apiKeyHelper',None)
        settings['env']={k:v for k,v in settings.get('env',{}).items()
            if k.upper() != 'ANTHROPIC_CUSTOM_HEADERS'
            and not any(s in k.upper() for s in ('TOKEN','SECRET','PASSWORD','API_KEY','AUTH','CONFIG_DIR'))}
        write_json(code/name,settings)
    for name in ('CLAUDE.md','RTK.original.md'):
        if (source/name).is_file():
            if (code/name).is_symlink(): raise ValueError('Lien inattendu : '+name)
            shutil.copyfile(source/name,code/name)
    # Copy personal definitions only. Do not copy plugin state, sessions or credentials.
    for name in ('skills','agents','commands','rules','output-styles'):
        if (source/name).is_dir():
            dest=code/name
            if dest.is_symlink(): raise ValueError('Lien inattendu : '+str(dest))
            # Reject destination links so syncing cannot write back into the original profile.
            if dest.exists():
                for base, dirs, files in os.walk(dest):
                    for entry in dirs+files:
                        if (Path(base)/entry).is_symlink():
                            raise ValueError('Lien inattendu : '+str(Path(base)/entry))
            shutil.copytree(source/name,dest,dirs_exist_ok=True,symlinks=False,
                ignore=shutil.ignore_patterns('.git','node_modules','__pycache__','.DS_Store'))
    mixed=read_json(code/'.claude.json')
    mixed['mcpServers']=read_json(Path.home()/'.claude.json').get('mcpServers',{})
    write_json(code/'.claude.json',mixed)
    # MCP definitions can contain their own service credentials; these are intentionally reused.
    # No desktop cookies, auth state or credentials files are read/copied.


def install(name, shared=True):
    code,data=paths(name)
    # Reject broken editable configuration before creating a partial profile.
    for source in (Path.home()/'.claude/settings.json',Path.home()/'.claude/settings.local.json',Path.home()/'.claude.json'):
        if not isinstance(read_json(source),dict):
            raise ValueError('Objet JSON attendu : '+str(source))
    dest_app=Path.home()/('Applications/Claude Profiles/Claude '+name.upper()+'.app')
    for p in (code,data,dest_app):
        if p.exists() or p.is_symlink():
            raise ValueError('Emplacement existant, aucun remplacement : '+str(p))
    if not APP.is_dir(): raise ValueError('Claude.app absent de /Applications')
    ROOT.mkdir(parents=True,exist_ok=True,mode=0o700)
    script=ROOT/'claude-profiles.py'
    if Path(__file__).resolve()!=script.resolve():
        shutil.copyfile(__file__,script)
    runtime=ROOT/'python'
    if not runtime.exists() and not runtime.is_symlink():
        runtime.symlink_to(Path(sys.executable).resolve())
    runtime.resolve(strict=True)
    code.mkdir(mode=0o700)
    data.mkdir(mode=0o700)
    # Start with an empty Desktop profile. No migration from personal Desktop.
    sync(code)
    contents=dest_app/'Contents'
    (contents/'MacOS').mkdir(parents=True)
    launcher=contents/'MacOS/launch'
    import shlex
    launcher.write_text('#!/bin/sh\nexec '+shlex.quote(str(runtime))+' '+shlex.quote(str(script))+' launch '+shlex.quote(name)+'\n')
    launcher.chmod(0o755)
    with (contents/'Info.plist').open('wb') as f:
        plistlib.dump({'CFBundleName':'Claude '+name.upper(),
            'CFBundleDisplayName':'Claude '+name.upper(),
            'CFBundleIdentifier':'local.claudeprofiles.'+name,
            'CFBundleExecutable':'launch','CFBundlePackageType':'APPL',
            'CFBundleVersion':'1','LSUIElement':True},f)
    write_json(code/'profile-launcher.json',{'profile':name,'version':1,'sharedConfig':shared})
    print('Profil créé :',code)
    print('Raccourci :',dest_app)
    print('Rien lancé. Ouvrez le raccourci pour connecter le nouveau compte.')
    print('Plugins à installer séparément dans ce profil.')


def launch(name):
    code,data=paths(name)
    if code.is_symlink() or data.is_symlink(): raise ValueError('Les profils doivent être des dossiers réels.')
    if read_json(code/'profile-launcher.json').get('profile')!=name:
        raise ValueError('Profil non installé par ce lanceur.')
    import fcntl
    with (code/'launcher.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        pids=processes(data)
        if pids:
            # Target the exact process, not the shared Claude bundle identifier.
            subprocess.run(['/usr/bin/osascript','-e',
                'tell application "System Events" to set frontmost of first process whose unix id is '+str(pids[0])+' to true'],check=True)
            return
        if read_json(code/'profile-launcher.json').get('sharedConfig',True):
            sync(code)
        subprocess.run(['/usr/bin/open','-n','-a',str(APP),
            '--env','CLAUDE_CONFIG_DIR='+str(code),
            '--env','CLAUDE_USER_DATA_DIR='+str(data),
            '--args','--user-data-dir='+str(data)],check=True)
        # Wait for registration while holding the lock to avoid repeated launches.
        import time
        for _ in range(40):
            if processes(data):
                print('Instance démarrée. Identité et configuration Code restent à vérifier dans l’application.')
                return
            time.sleep(.25)
        raise RuntimeError('Processus non confirmé. Vérifier les fenêtres avant de relancer.')


def profiles():
    home=Path.home()
    personal=processes(None)
    result=[{'id':'__personal__','name':'Personnel','code':str(home/'.claude'),
        'data':str(home/'Library/Application Support/Claude'),
        'app':str(APP),'shared':False,'managed':False,'pid':personal[0] if personal else None}]
    for code in sorted(home.glob('.claude-*')):
        marker=code/'profile-launcher.json'
        if not marker.is_file():
            continue
        config=read_json(marker)
        name=config['profile']
        expected,data=paths(name)
        if code!=expected or code.is_symlink() or data.is_symlink():
            raise ValueError('Emplacement de profil inattendu : '+str(code))
        pids=processes(data)
        result.append({'id':name,'name':name.upper(),'code':str(code),'data':str(data),
            'app':str(home/('Applications/Claude Profiles/Claude '+name.upper()+'.app')),
            'shared':config.get('sharedConfig',True),'managed':True,'pid':pids[0] if pids else None})
    return result


def configure(name, shared):
    code,data=paths(name)
    marker=code/'profile-launcher.json'
    config=read_json(marker)
    if code.is_symlink() or config.get('profile')!=name:
        raise ValueError('Profil non installé par ce lanceur.')
    config['sharedConfig']=shared
    write_json(marker,config)
    print('Configuration commune au prochain lancement.' if shared else 'Configuration indépendante conservée.')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['install','launch','list','configure','sync'])
    parser.add_argument('name',nargs='?')
    parser.add_argument('--independent',action='store_true')
    args=parser.parse_args()
    try:
        if args.action=='list':
            print(json.dumps(profiles(),ensure_ascii=False))
        else:
            if args.name is None:
                parser.error('Un nom de profil est nécessaire.')
            if args.action=='install':
                install(args.name,not args.independent)
            elif args.action=='configure':
                configure(args.name,not args.independent)
            elif args.action=='sync':
                code,data=paths(args.name)
                config=read_json(code/'profile-launcher.json')
                if code.is_symlink() or config.get('profile')!=args.name:
                    raise ValueError('Profil non installé par ce lanceur.')
                if not config.get('sharedConfig',True):
                    raise ValueError('Ce profil utilise une configuration indépendante.')
                if processes(data):
                    raise ValueError('Quittez cette instance Claude avant de synchroniser.')
                sync(code)
                print('Configuration commune synchronisée.')
            else:
                launch(args.name)
    except Exception as e:
        print('ERREUR :',e,file=sys.stderr)
        return 1
    return 0

if __name__=='__main__':
    sys.exit(main())
