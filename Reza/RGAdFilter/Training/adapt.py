#!/usr/bin/env python3
"""Domain adaptation with explicit authored labels and replay from the original TRAIN split.

The original validation split selects the checkpoint/threshold. The original test split
is evaluated only after selection. Real device development probes are not reported as unseen.
"""
import argparse,json,random,time,hashlib
from pathlib import Path
import numpy as np
import torch
from torch.utils.data import DataLoader,TensorDataset,WeightedRandomSampler
from transformers import BertForSequenceClassification,BertTokenizer
from opencc import OpenCC
from train import normalize,metrics
from token_windows import native_windows

ap=argparse.ArgumentParser();ap.add_argument('--source',required=True);ap.add_argument('--examples',required=True);ap.add_argument('--output',required=True);ap.add_argument('--epochs',type=int,default=4);ap.add_argument('--domain-validation')
ap.add_argument('--content-weight',type=float,default=18);ap.add_argument('--promotion-weight',type=float,default=18)
ap.add_argument('--learning-rate',type=float,default=3e-5)
ap.add_argument('--focus-examples',help='Reviewed difficult training examples (content/promotion arrays); never validation inputs')
ap.add_argument('--focus-all-windows',action='store_true',help='Replay exact native token windows for focused training examples')
ap.add_argument('--focus-weight-multiplier',type=float,default=5,help='Sampling multiplier for explicitly reviewed difficult training examples')
a=ap.parse_args();source=Path(a.source);out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
assert 0 < a.content_weight <= 100 and 0 < a.promotion_weight <= 100
assert 0 < a.learning_rate <= 1e-3
assert 1 <= a.focus_weight_multiplier <= 50
assert not a.focus_all_windows or a.focus_examples, 'Window replay requires explicit reviewed focus examples'
random.seed(34657);np.random.seed(34657);torch.manual_seed(34657);torch.set_num_threads(3)
splits=json.loads((source/'split.json').read_text());original=json.loads((source/'metrics.json').read_text());examples=json.loads(Path(a.examples).read_text());cc=OpenCC('s2t')
focus=set()
if a.focus_examples:
 for label,key in [(0,'content'),(1,'promotion')]:
  for text in json.loads(Path(a.focus_examples).read_text())[key]:
   for variant in (text,cc.convert(text)):focus.add((label,normalize(variant)))
additions=[];seen=set()
for label,key in [(0,'content'),(1,'promotion')]:
 for i,text in enumerate(examples[key]):
  for variant in (text,cc.convert(text)):
   text=normalize(variant)
   if (label,text) in seen:continue
   seen.add((label,text));additions.append(dict(text=text,label=label,group=f'authored-{key}-{i}',weight=(a.promotion_weight if label else a.content_weight)*(a.focus_weight_multiplier if (label,text) in focus else 1)))
assert focus.issubset(seen), 'Focused examples must already have reviewed training labels'
assert not {t for label,t in seen if label==0}.intersection(t for label,t in seen if label==1), 'Normalized training label conflict; review before fitting'
# Replay is drawn only from training. No validation/test input is promoted into training.
pool=[r for r in splits['train'] if not r.get('group','').startswith('authored-')] if a.domain_validation else splits['train']
replay=random.sample(pool,min(8000,len(pool)))
t=BertTokenizer.from_pretrained(source/'checkpoint')
window_rows=[]
if a.focus_all_windows:
 for row in additions:
  if (row['label'],row['text']) not in focus:continue
  tokens=t.encode(row['text'],add_special_tokens=False)
  windows=native_windows(tokens)
  if windows is None or not 1 < len(windows) <= 8:continue
  for ids in windows:
   # Keep IDs directly: decoding a window that starts with a continuation subword
   # would change the input on retokenization.
   window_rows.append(dict(row,native_window_ids=ids))
additions+=window_rows
rows=replay+additions+splits['validation']+splits['test']
partitions=dict(train=np.arange(len(replay)+len(additions)),validation=np.arange(len(replay)+len(additions),len(replay)+len(additions)+len(splits['validation'])),test=np.arange(len(rows)-len(splits['test']),len(rows)))
(out/'split.json').write_text(json.dumps({k:[rows[int(i)] for i in v] for k,v in partitions.items()},ensure_ascii=False))
x=t([r['text'] for r in rows],padding='max_length',truncation=True,max_length=128,return_tensors='pt');labels=torch.tensor([r['label'] for r in rows])
for i,row in enumerate(rows[:len(replay)+len(additions)]):
 if 'native_window_ids' in row:
  x['input_ids'][i]=torch.tensor(row['native_window_ids']);x['attention_mask'][i]=(x['input_ids'][i]!=0).long()
domain=[]
if a.domain_validation:
 validation=json.loads(Path(a.domain_validation).read_text())
 domain=[dict(text=normalize(text),label=label) for label,key in [(0,'content'),(1,'promotion')] for text in validation[key]]
 assert not {r['text'] for r in domain}.intersection(r['text'] for r in rows[:len(replay)+len(additions)]), 'Domain validation overlaps training'
 domain_x=t([r['text'] for r in domain],padding='max_length',truncation=True,max_length=128,return_tensors='pt')
 domain_y=np.asarray([r['label'] for r in domain])
def loader(indices,train=False):
 sampler=WeightedRandomSampler([rows[int(i)].get('weight',1) for i in indices],len(indices),replacement=True) if train else None
 return DataLoader(TensorDataset(x['input_ids'][indices],x['attention_mask'][indices],labels[indices]),batch_size=32,sampler=sampler)
m=BertForSequenceClassification.from_pretrained(source/'checkpoint',attn_implementation='eager');device='mps' if torch.backends.mps.is_available() else 'cpu'
# Preserve the general encoder; adapt the upper layers and classification head to channel text.
for p in m.bert.embeddings.parameters():p.requires_grad=False
for layer in m.bert.encoder.layer[:4]:
 for p in layer.parameters():p.requires_grad=False
m.to(device);optimizer=torch.optim.AdamW([p for p in m.parameters() if p.requires_grad],lr=a.learning_rate,weight_decay=.01);loss_fn=torch.nn.CrossEntropyLoss(weight=torch.tensor([1.5,1.],device=device))
def predict(indices):
 m.eval();scores=[]
 with torch.no_grad():
  for ids,mask,_ in loader(indices):scores.extend(m(input_ids=ids.to(device),attention_mask=mask.to(device)).logits.softmax(-1)[:,1].cpu().tolist())
 return np.asarray(scores)
history=[];best=None
print(json.dumps(dict(replay=len(replay),authored=len(additions),splits={k:len(v) for k,v in partitions.items()})),flush=True)
for epoch in range(a.epochs):
 start=time.time();m.train();total=0
 for step,(ids,mask,y) in enumerate(loader(partitions['train'],True)):
  optimizer.zero_grad(set_to_none=True);loss=loss_fn(m(input_ids=ids.to(device),attention_mask=mask.to(device)).logits,y.to(device));loss.backward();torch.nn.utils.clip_grad_norm_(m.parameters(),1);optimizer.step();total+=loss.item()
  if step%50==0:print(json.dumps(dict(epoch=epoch+1,step=step,loss=loss.item(),seconds=round(time.time()-start,1))),flush=True)
 scores=predict(partitions['validation']);y=labels[partitions['validation']].numpy()
 # Match calibrate.py: the coarse grid skips useful saturated-score thresholds.
 grid=np.unique(np.concatenate([np.linspace(.8,.99,381),np.linspace(.99,.9999,991)]))
 candidates=[metrics(y,scores,float(t)) for t in grid];acceptable=[v for v in candidates if v['false_positive_rate']<=.005 and v['precision']>=.985 and v['tp']>0]
 domain_scores=None
 if domain:
  with torch.no_grad():domain_scores=m(input_ids=domain_x['input_ids'].to(device),attention_mask=domain_x['attention_mask'].to(device)).logits.softmax(-1)[:,1].cpu().numpy()
 def quality_for(candidate):
  if domain_scores is None:return (0,0,candidate['recall'])
  dm=metrics(domain_y,domain_scores,candidate['threshold'])
  return (-dm['fp'],dm['recall'],candidate['recall'])
 chosen=max(acceptable,key=quality_for) if acceptable else metrics(y,scores,.9995)
 record=dict(epoch=epoch+1,loss=total/(step+1),seconds=time.time()-start,validation=chosen)
 if domain_scores is not None:record['domain_validation']=metrics(domain_y,domain_scores,chosen['threshold'])
 history.append(record);print(json.dumps(record),flush=True)
 quality=quality_for(chosen) if acceptable else (-10000,-1,-chosen['false_positive_rate'])
 if best is None or quality>best:
  best=quality;m.save_pretrained(out/'checkpoint');t.save_pretrained(out/'checkpoint');(out/'selected.json').write_text(json.dumps(record,indent=2))
m=BertForSequenceClassification.from_pretrained(out/'checkpoint',attn_implementation='eager').to(device);selected=json.loads((out/'selected.json').read_text());scores=predict(partitions['test']);y=labels[partitions['test']].numpy()
r=dict(cleaning=original['cleaning'],history=history,selected=selected,test=metrics(y,scores,selected['validation']['threshold']),data_sha256=original['data_sha256'],max_length=128,parameters=sum(p.numel() for p in m.parameters()),adaptation=dict(replay=len(replay),authored=len(additions),examples_sha256=hashlib.sha256(Path(a.examples).read_bytes()).hexdigest(),source_selected=original['selected']))
if a.domain_validation:r['adaptation']['domain_validation_sha256']=hashlib.sha256(Path(a.domain_validation).read_bytes()).hexdigest()
r['adaptation']['samplingWeights']={'content':a.content_weight,'promotion':a.promotion_weight}
r['adaptation']['learningRate']=a.learning_rate
if a.focus_examples:r['adaptation']['focus']={'sha256':hashlib.sha256(Path(a.focus_examples).read_bytes()).hexdigest(),'normalizedRows':len(focus),'weightMultiplier':a.focus_weight_multiplier}
r['adaptation']['exactNativeWindowRows']=len(window_rows)
(out/'metrics.json').write_text(json.dumps(r,indent=2));print(json.dumps(dict(final_test=r['test'])),flush=True)
