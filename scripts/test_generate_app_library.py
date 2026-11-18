import copy
import importlib.util
import json
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('generator',ROOT/'scripts/generate_app_library.py')
generator=importlib.util.module_from_spec(spec); spec.loader.exec_module(generator)

class AppLibraryGenerationTests(unittest.TestCase):
    def setUp(self):
        self.data=json.loads((ROOT/'packages/app_library/catalog.json').read_text('utf-8'))
        self.icons=json.loads((ROOT/'packages/app_icon_catalog/catalog.json').read_text('utf-8'))
    def invalid(self,change):
        data=copy.deepcopy(self.data); change(data)
        with self.assertRaises(ValueError): generator.validate(data,self.icons)
    def test_all_mirrors_are_current(self):
        self.assertEqual(generator.generate(check=True),60)
    def test_explicit_platforms_and_identity(self):
        safari=next(a for a in self.data['apps'] if a['id']=='safari')
        self.assertEqual(safari['supportedOS'],['macos'])
        self.assertFalse(any(a['id']=='codex' for a in self.data['apps']))
        github=next(a for a in self.data['apps'] if a['id']=='github-desktop')
        self.assertNotIn('linux',github['supportedOS'])
    def test_forbidden_action_types_and_raw_commands(self):
        self.invalid(lambda d:d['apps'][0]['libraries'][0]['actions'][0].update(command='shell'))
        for keys in [['CTRL','/private/app'],['CTRL'],['CTRL','A','B'],['CTRL','CTRL','C'],['CTRL','[']]:
            self.invalid(lambda d,k=keys:d['apps'][0]['libraries'][0]['actions'][0].update(keys=k))
    def test_wrong_boolean_schema_types(self):
        self.invalid(lambda d:d.update(schemaVersion=1.0))
        self.invalid(lambda d:d['apps'][0].update(bundled=1))
        self.invalid(lambda d:d['apps'][0]['libraries'][0]['actions'][0].update(requiresConfiguration=0))
    def test_os_family_and_duplicate_availability(self):
        self.invalid(lambda d:d['apps'][0]['libraries'][0].update(supportedOS=['windows']))
        self.invalid(lambda d:d['apps'][0].update(supportedOS=['macos','macos']))
        self.invalid(lambda d:d['apps'][0]['libraries'][0].update(supportedOS=['macos','macos']))
    def test_lengths_urls_and_duplicates(self):
        for url in ['http://example.com','https:///missing','https://user@example.com','https://example.com/#fragment']:
            self.invalid(lambda d,u=url:d['apps'][0]['libraries'][0].update(sourceUrls=[u]))
        self.invalid(lambda d:d['apps'][0].update(name='x'*121))
        self.invalid(lambda d:d['apps'][0]['libraries'][0]['actions'][0].update(title='x'*81))
        self.invalid(lambda d:d['apps'][0]['libraries'][0]['actions'][1].update(id=d['apps'][0]['libraries'][0]['actions'][0]['id']))
    def test_unassigned_is_explicit_and_nonexecuting(self):
        actions=[x for a in self.data['apps'] for l in a['libraries'] for x in l['actions']]
        self.assertGreater(sum(bool(x['keys']) for x in actions),400)
        self.assertGreater(sum(not x['keys'] for x in actions),0)
        self.assertTrue(all(x['requiresConfiguration']==(not x['keys']) for x in actions))
    def test_named_punctuation_and_vscode_linux_safety(self):
        libs=next(a for a in self.data['apps'] if a['id']=='vscode')['libraries']
        self.assertTrue(all(any(x['id']=='quick-fix' and x['keys'][-1]=='PERIOD' for x in l['actions']) for l in libs))
        for a in self.data['apps']:
            for l in a['libraries']:
                for action in l['actions']:
                    self.assertLessEqual(len(action['keys']),5)

if __name__=='__main__': unittest.main()
