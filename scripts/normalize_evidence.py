"""Replace machine-specific home paths in exported evidence, after comparisons."""
import argparse,re
from pathlib import Path

def normalize(text):
 text=text.replace(str(Path(__file__).resolve().parents[1]),'<repo>')
 return re.sub('/'+'Users'+r'/[^\s"\'<>\\]+',lambda m:'<external>/'+m[0].rsplit('/',1)[-1],text)

def main():
 p=argparse.ArgumentParser();p.add_argument('paths',nargs='*',default=['docs/evidence']);a=p.parse_args()
 for name in a.paths:
  path=Path(name)
  for f in path.rglob('*') if path.is_dir() else [path]:
   if f.is_file() and f.suffix in ['.json','.log','.md']:
    old=f.read_text();new=normalize(old)
    if old!=new:f.write_text(new)
if __name__=='__main__':main()
