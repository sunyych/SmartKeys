"""Generate self-contained strict App library DTOs and the server registry."""
import argparse
import json
import re
import hashlib
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = Path('packages/app_library')
APPS = [Path('.'), Path('desktop_companion'), Path('apps/bluetooth')]
MODIFIERS = {'CTRL', 'ALT', 'SHIFT', 'META'}
NAMED_KEYS = {'ENTER','ESC','BACKSPACE','TAB','SPACE','LEFT','RIGHT','UP','DOWN','DELETE','HOME','END','PAGE_UP','PAGE_DOWN','MINUS','EQUAL','LEFT_BRACKET','RIGHT_BRACKET','BACKSLASH','SEMICOLON','QUOTE','BACKTICK','COMMA','PERIOD','SLASH'}
KEYS = NAMED_KEYS | set('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789') | {f'F{i}' for i in range(1,13)}

def _validate(data, icons):
    def text(value, limit):
        if not isinstance(value,str) or not value or value != value.strip() or len(value.encode('utf-16-le'))//2 > limit or any(ord(c)<32 or ord(c)==127 for c in value):
            raise ValueError('Invalid bounded text')
        return value
    def check_identity(value):
        text(value,80)
        if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]{0,79}',value) or value.startswith('installed.'):
            raise ValueError('Invalid public identity')
    def strings(value,limit):
        if not isinstance(value,list) or len(value)>limit: raise ValueError('Invalid string array')
        for v in value: text(v,2048)
        if len(set(value))!=len(value): raise ValueError('Duplicate string')
    def check_platforms(value):
        strings(value,3)
        if not value or not set(value)<={'macos','windows','linux'}: raise ValueError('Invalid OS')
    if set(data) != {'schemaVersion','version','apps'} or data['schemaVersion'] != 1:
        raise ValueError('Invalid App catalog envelope')
    if type(data['schemaVersion']) is not int or not isinstance(data['apps'],list) or not 1<=len(data['apps'])<=256:
        raise ValueError('Invalid catalog size/schema')
    text(data['version'],80)
    if {a['id'] for a in data['apps']} != {a['id'] for a in icons['icons']}:
        raise ValueError('App catalog must cover the exact canonical icon registry')
    identities, library_ids = set(), set()
    by_icon = {a['id']: a for a in icons['icons']}
    for app in data['apps']:
        if set(app) != {'id','iconId','name','aliases','bundled','supportedOS','libraries'} or app['iconId'] != app['id'] or app['bundled'] != by_icon[app['id']]['bundled']:
            raise ValueError('Invalid App identity')
        check_identity(app['id']); check_identity(app['iconId']); text(app['name'],120); strings(app['aliases'],16); check_platforms(app['supportedOS'])
        if type(app['bundled']) is not bool or not isinstance(app['libraries'],list) or not 1<=len(app['libraries'])<=2:
            raise ValueError('Invalid App fields')
        if app['aliases'] != by_icon[app['id']]['aliases']:
            raise ValueError('App aliases must match real product aliases')
        for identity in [app['id'], *app['aliases']]:
            check_identity(identity)
            if identity.casefold() == 'codex' or identity.casefold() in identities:
                raise ValueError('Duplicate or legacy product identity')
            identities.add(identity.casefold())
        os = set(app['supportedOS'])
        if not os or not os <= {'macos','windows','linux'} or len(os) != len(app['supportedOS']):
            raise ValueError('Invalid OS availability')
        families, covered = set(), set()
        for lib in app['libraries']:
            if set(lib) != {'id','family','supportedOS','version','sourceUrls','actions','context'} or lib['family'] in families:
                raise ValueError('Invalid shortcut library')
            families.add(lib['family'])
            text(lib['id'],80)
            if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]{0,79}',lib['id']) or lib['id'].startswith('installed.') or lib['id'] in library_ids:
                raise ValueError('Invalid or duplicate library ID')
            library_ids.add(lib['id']); text(lib['version'],80); check_platforms(lib['supportedOS']); strings(lib['sourceUrls'],12)
            for source in lib['sourceUrls']:
                uri=urlsplit(source)
                if uri.scheme!='https' or not uri.hostname or uri.username is not None or uri.password is not None or uri.fragment:
                    raise ValueError('Invalid source URL')
            allowed = {'macos'} if lib['family'] == 'macos' else {'windows','linux'} if lib['family'] == 'windowsLinux' else set()
            platforms = set(lib['supportedOS'])
            if not platforms or not platforms <= os & allowed or lib['context'] not in {'native','web','terminal'}:
                raise ValueError('Invalid family/context availability')
            covered |= platforms
            if not lib['id'].startswith(app['id'] + '.') or not lib['sourceUrls'] or any(not u.startswith('https://') for u in lib['sourceUrls']):
                raise ValueError('Invalid library identity/provenance')
            if not 1 <= len(lib['actions']) <= 12:
                raise ValueError('Invalid action count')
            ids = set()
            for action in lib['actions']:
                if set(action) != {'id','title','keys','requiresConfiguration'} or action['id'] in ids:
                    raise ValueError('Invalid action identity')
                ids.add(action['id'])
                text(action['id'],80); text(action['title'],80)
                if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]{0,79}',action['id']) or action['id'].startswith('installed.'):
                    raise ValueError('Invalid action ID')
                keys = action['keys']
                strings(keys,5)
                if type(action['requiresConfiguration']) is not bool or action['requiresConfiguration'] != (not keys):
                    raise ValueError('Invalid unassigned action')
                if keys and (len(keys) > 5 or keys[-1] not in KEYS or not set(keys[:-1]) <= MODIFIERS or len(set(keys)) != len(keys)):
                    raise ValueError('Invalid public keyboard chord')
        if covered != os:
            raise ValueError('Library platforms must cover App availability')
    return data

def validate(data, icons):
    try:
        return _validate(data,icons)
    except (KeyError, TypeError, AttributeError) as error:
        raise ValueError('Invalid App library schema') from error

def generate(root=ROOT, check=False, full_only=False):
    icons = json.loads((root/'packages/app_icon_catalog/catalog.json').read_text('utf-8'))
    data = validate(json.loads((root/PACKAGE/'catalog.json').read_text('utf-8')), icons)
    raw = json.dumps(data, ensure_ascii=False, separators=(',',':'))
    hashes = {i['id']:i['sha256'] for i in icons['icons']}
    action_hashes = {lib['id']:{a['id']:hashlib.sha256(json.dumps(a,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest() for a in lib['actions']} for app in data['apps'] for lib in app['libraries']}
    model = (root/PACKAGE/'model.dart.template').read_text('utf-8').replace('__CATALOG_JSON__',raw).replace('__ICON_HASHES__',json.dumps(hashes,sort_keys=True)).replace('__ACTION_HASHES__',json.dumps(action_hashes,sort_keys=True))
    expected = {app/'lib/app_library/app_library.dart': model.encode('utf-8') for app in (APPS[:2] if full_only else APPS)}
    expected[Path('community_server/assets/app_library/catalog.json')] = (json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    stale = []
    for relative, content in expected.items():
        path = root/relative
        if path.is_symlink(): raise ValueError('Generated libraries cannot be links')
        if not path.exists() or path.read_bytes() != content:
            stale.append(str(relative))
            if not check:
                path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes(content)
    if check and stale: raise ValueError('Stale App libraries: '+', '.join(stale))
    return len(data['apps'])

if __name__ == '__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--check',action='store_true'); parser.add_argument('--full-only',action='store_true')
    args=parser.parse_args(); print(f'Validated {generate(check=args.check,full_only=args.full_only)} App library records')
