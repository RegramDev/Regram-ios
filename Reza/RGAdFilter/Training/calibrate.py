#!/usr/bin/env python3
"""Refine a saturated classifier's threshold on validation only, then report test metrics.

The original coarse grid has only one point above .999. Refinement preserves the same
precision/FPR constraints and domain-selection priority; it never fits test labels.
Raw messages and probability arrays stay in ignored local directories.
"""
import argparse, hashlib, json
from pathlib import Path
import numpy as np
import torch
from transformers import BertForSequenceClassification, BertTokenizer
from train import normalize, metrics

p = argparse.ArgumentParser()
p.add_argument('--training', required=True, type=Path)
p.add_argument('--domain-validation', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
a = p.parse_args()
torch.set_num_threads(3)
record = json.loads((a.training / 'metrics.json').read_text())
splits = json.loads((a.training / 'split.json').read_text())
domain = json.loads(a.domain_validation.read_text())
domain = [dict(text=normalize(text), label=label) for label, key in [(0, 'content'), (1, 'promotion')] for text in domain[key]]
assert not {r['text'] for r in domain}.intersection(r['text'] for r in splits['train'])
device = 'mps' if torch.backends.mps.is_available() else 'cpu'
model = BertForSequenceClassification.from_pretrained(a.training / 'checkpoint', attn_implementation='eager').to(device).eval()
tokenizer = BertTokenizer.from_pretrained(a.training / 'checkpoint')
def score(rows):
    probabilities = []
    for offset in range(0, len(rows), 32):
        inputs = tokenizer([r['text'] for r in rows[offset:offset + 32]], padding='max_length', truncation=True, max_length=record['max_length'], return_tensors='pt')
        with torch.no_grad():
            probabilities.extend(model(input_ids=inputs['input_ids'].to(device), attention_mask=inputs['attention_mask'].to(device)).logits.softmax(-1)[:, 1].cpu().tolist())
    return np.asarray([r['label'] for r in rows]), np.asarray(probabilities)
y, scores = score(splits['validation'])
domain_y, domain_scores = score(domain)
grid = np.unique(np.concatenate([np.linspace(.8, .99, 381), np.linspace(.99, .9999, 991)]))
candidates = [metrics(y, scores, float(threshold)) for threshold in grid]
acceptable = [v for v in candidates if v['false_positive_rate'] <= .005 and v['precision'] >= .985 and v['tp'] > 0]
if not acceptable:
    raise RuntimeError('No threshold satisfies the existing validation constraints')
def quality(candidate):
    d = metrics(domain_y, domain_scores, candidate['threshold'])
    return (-d['fp'], d['recall'], candidate['recall'])
selected = max(acceptable, key=quality)
test_y, test_scores = score(splits['test'])
result = dict(previousThreshold=record['selected']['validation']['threshold'], validation=selected,
              domainValidation=metrics(domain_y, domain_scores, selected['threshold']),
              test=metrics(test_y, test_scores, selected['threshold']),
              domainSHA256=hashlib.sha256(a.domain_validation.read_bytes()).hexdigest(),
              method='Validation-only fine grid; same public precision/FPR constraints and domain priorities; test evaluated after selection')
a.output.write_text(json.dumps(result, indent=2))
print(json.dumps(result), flush=True)
