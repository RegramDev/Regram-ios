#!/usr/bin/env python3
"""Extract only text/label from explicit local public-corpus files; never preserve account IDs.

This script does not fetch corpora. Obtain/review the pinned sources and their terms first.
Outputs must be kept in ignored build-input, together with the raw input files.
"""
import argparse,csv,json,hashlib
from pathlib import Path
from opencc import OpenCC
from train import normalize
ap=argparse.ArgumentParser();ap.add_argument('--sniper',required=True);ap.add_argument('--olivi',required=True);ap.add_argument('--examples',required=True);ap.add_argument('--output',required=True);a=ap.parse_args();out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
rows=[]
for r in csv.DictReader(open(a.olivi)):
 if r.get('label') in ('0','1') and isinstance(r.get('text'),str):rows.append(dict(label=r['label'],text=r['text']))
for r in csv.DictReader(open(a.sniper)):
 if r['training_target']=='message_content' and r['message_type'] in ('ham','spam') and r['marked_by'] in ('admin_dashboard','group_admin'):
  rows.append(dict(label=int(r['message_type']=='spam'),text=r['message']))
with (out/'combined.csv').open('w') as f:
 w=csv.DictWriter(f,fieldnames=['label','text']);w.writeheader();w.writerows(rows)
examples=json.loads(Path(a.examples).read_text());cc=OpenCC('s2t');seen=set();extras=[]
for label,key in [(0,'content'),(1,'promotion')]:
 for i,text in enumerate(examples[key]):
  for variant in (text,cc.convert(text)):
   normalized=normalize(variant)
   if (label,normalized) in seen:continue
   seen.add((label,normalized));extras.append(dict(text=normalized,label=label,group=f'authored-{key}-{i}',weight=8))
(out/'domain.jsonl').write_text('\n'.join(json.dumps(r,ensure_ascii=False) for r in extras)+'\n')
print(json.dumps(dict(publicRows=len(rows),authoredRows=len(extras),sha256=hashlib.sha256((out/'combined.csv').read_bytes()).hexdigest())))
