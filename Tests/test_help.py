import importlib.util,json,pathlib,subprocess,tempfile,shutil,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class HelpTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.tmp.name)
  for path in ['Sources','docs','scripts']:shutil.copytree(ROOT/path,self.root/path)
  for path in ['Info.plist','build.command']:shutil.copy(ROOT/path,self.root/path)
 def tearDown(self):self.tmp.cleanup()
 def runcheck(self):return subprocess.run(['python3',str(self.root/'scripts/check_help.py')],capture_output=True).returncode
 def test_valid(self):self.assertEqual(self.runcheck(),0)
 def test_source_drift(self):
  p=self.root/'Sources/Controls.swift';p.write_text(p.read_text()+'\n// changed\n');self.assertNotEqual(self.runcheck(),0)
 def test_docs_drift(self):
  p=self.root/'docs/Help.json';p.write_text(p.read_text()+'\n');self.assertNotEqual(self.runcheck(),0)
 def test_missing_resource(self):
  (self.root/'docs/Help.json').unlink();self.assertNotEqual(self.runcheck(),0)
 def test_duplicate_id(self):
  p=self.root/'docs/Help.json';d=json.loads(p.read_text());d['sections'][1]['id']=d['sections'][0]['id'];p.write_text(json.dumps(d));self.assertNotEqual(self.runcheck(),0)
if __name__=='__main__':unittest.main()
