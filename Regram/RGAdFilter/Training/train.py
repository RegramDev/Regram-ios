#!/usr/bin/env python3
"""Local, reproducible MiniRBT fine-tuning. Raw corpora and checkpoints stay outside Git.

Input: CSV with text,label (0=content, 1=promotion); optional reviewed JSONL with
text,label,group. Grouped splits are made BEFORE training or augmentation. The
held-out test set is never used for checkpoint or threshold selection.
"""
import argparse
import csv
import hashlib
import json
import random
import re
import time
import unicodedata
from pathlib import Path

import numpy as np
import torch
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics import confusion_matrix, precision_recall_fscore_support
from sklearn.model_selection import GroupShuffleSplit
from sklearn.neighbors import NearestNeighbors
from torch.utils.data import DataLoader, TensorDataset, WeightedRandomSampler
from transformers import BertForSequenceClassification, BertTokenizer


def normalize(text):
    text = unicodedata.normalize('NFKC', text).lower()
    text = ''.join(c for c in text if unicodedata.category(c) not in ('Cf', 'Mn', 'Me', 'So', 'Sk'))
    text = re.sub(r'https?://[^\s<>]+|(?:t\.me|telegram\.me)/[^\s<>]+', ' 链接 ', text)
    text = re.sub(r'@[a-zA-Z0-9_]{1,32}', ' 用户 ', text)
    text = re.sub(r'[0-9]{5,}', ' 数字 ', text)
    text = re.sub(r'(?<=[\u3400-\u9fff])\s+(?=[\u3400-\u9fff])', '', text)
    return re.sub(r'\s+', ' ', text).strip()


def prepare(csv_path, extra):
    unique, conflicts, malformed = {}, set(), 0
    for row in csv.DictReader(open(csv_path)):
        if row.get('label') not in ('0', '1') or not isinstance(row.get('text'), str):
            malformed += 1
            continue
        text = normalize(row['text'])
        if not 4 <= len(text) <= 2048:
            continue
        key = re.sub(r'[\W\d_]+', '', text)
        label = int(row['label'])
        if key in unique and unique[key]['label'] != label:
            conflicts.add(key)
        unique.setdefault(key, dict(text=text, label=label))
    rows = [v for k, v in unique.items() if k not in conflicts]
    parent = list(range(len(rows)))
    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    # Keep near-duplicate advertising campaigns out of opposite splits.
    x = TfidfVectorizer(analyzer='char', ngram_range=(3, 4), min_df=2, max_features=60000).fit_transform([r['text'] for r in rows])
    nn = NearestNeighbors(metric='cosine', algorithm='brute', n_jobs=2).fit(x)
    for start in range(0, len(rows), 128):
        distances, indices = nn.radius_neighbors(x[start:start+128], radius=0.15)
        for i, neighbors in enumerate(indices):
            for j in neighbors:
                a, b = root(start+i), root(int(j))
                if a != b:
                    parent[b] = a
    for i, row in enumerate(rows):
        row['group'] = 'public-' + str(root(i))
    additions = [dict(r, text=normalize(r['text'])) for r in map(json.loads, Path(extra).read_text().splitlines())] if extra else []
    extra_keys = {re.sub(r'[\W\d_]+', '', r['text']) for r in additions}
    rows = [r for r in rows if re.sub(r'[\W\d_]+', '', r['text']) not in extra_keys]
    indices = np.arange(len(rows))
    groups = [r['group'] for r in rows]
    train, rest = next(GroupShuffleSplit(n_splits=1, test_size=0.30, random_state=34655).split(indices, groups=groups))
    a, b = next(GroupShuffleSplit(n_splits=1, test_size=0.50, random_state=34656).split(rest, groups=[groups[i] for i in rest]))
    partitions = dict(train=train, validation=rest[a], test=rest[b])
    # Domain adaptations are declared training material, never counted as unseen test samples.
    if additions:
        partitions['train'] = np.concatenate((train, np.arange(len(rows), len(rows)+len(additions))))
        rows += additions
    return rows, partitions, dict(malformed=malformed, conflicting_duplicates=len(conflicts), deduplicated=len(rows), groups=len(set(groups)))


def metrics(labels, scores, threshold):
    prediction = scores >= threshold
    p, r, f, _ = precision_recall_fscore_support(labels, prediction, average='binary', zero_division=0)
    tn, fp, fn, tp = confusion_matrix(labels, prediction, labels=[0, 1]).ravel()
    return dict(threshold=float(threshold), precision=float(p), recall=float(r), f1=float(f), tn=int(tn), fp=int(fp), fn=int(fn), tp=int(tp), false_positive_rate=float(fp/max(1, tn+fp)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--extra')
    ap.add_argument('--base', required=True)
    ap.add_argument('--output', required=True)
    ap.add_argument('--epochs', type=int, default=5)
    ap.add_argument('--length', type=int, default=128)
    args = ap.parse_args()
    out = Path(args.output); out.mkdir(parents=True, exist_ok=True)
    random.seed(34655); np.random.seed(34655); torch.manual_seed(34655); torch.set_num_threads(4)
    rows, splits, cleaning = prepare(args.data, args.extra)
    (out/'split.json').write_text(json.dumps({k: [rows[int(i)] for i in v] for k, v in splits.items()}, ensure_ascii=False))
    print(json.dumps(dict(cleaning=cleaning, splits={k: len(v) for k,v in splits.items()})), flush=True)
    tokenizer = BertTokenizer.from_pretrained(args.base)
    encoded = tokenizer([r['text'] for r in rows], truncation=True, padding='max_length', max_length=args.length, return_tensors='pt')
    labels = torch.tensor([r['label'] for r in rows])
    def loader(indices, shuffle=False):
        sampler = WeightedRandomSampler([rows[int(i)].get('weight', 1.0) for i in indices], len(indices), replacement=True) if shuffle else None
        return DataLoader(TensorDataset(encoded['input_ids'][indices], encoded['attention_mask'][indices], labels[indices]), batch_size=32, sampler=sampler)
    model = BertForSequenceClassification.from_pretrained(args.base, num_labels=2, attn_implementation='eager')
    device = 'mps' if torch.backends.mps.is_available() else 'cpu'
    model.to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=3e-5, weight_decay=0.01)
    criterion = torch.nn.CrossEntropyLoss(weight=torch.tensor([1.5, 1.0], device=device))
    def predict(indices):
        model.eval(); result = []
        with torch.no_grad():
            for ids, mask, _ in loader(indices):
                result.extend(torch.softmax(model(input_ids=ids.to(device), attention_mask=mask.to(device)).logits, -1)[:, 1].cpu().tolist())
        return np.asarray(result)
    history, best = [], -1
    for epoch in range(args.epochs):
        started = time.time(); model.train(); total = 0
        for step, (ids, mask, y) in enumerate(loader(splits['train'], shuffle=True)):
            optimizer.zero_grad(set_to_none=True)
            logits = model(input_ids=ids.to(device), attention_mask=mask.to(device)).logits
            loss = criterion(logits, y.to(device)); loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); optimizer.step(); total += loss.item()
            if step % 50 == 0:
                print(json.dumps(dict(epoch=epoch+1, step=step, loss=round(loss.item(),5), seconds=round(time.time()-started,1))), flush=True)
        scores = predict(splits['validation']); y = labels[splits['validation']].numpy()
        candidates = [metrics(y, scores, t) for t in np.linspace(0.8, 0.9995, 400)]
        acceptable = [m for m in candidates if m['false_positive_rate'] <= 0.005 and m['precision'] >= 0.985 and m['tp'] >= 1]
        chosen = max(acceptable, key=lambda m:m['recall']) if acceptable else metrics(y, scores, 0.9995)
        record = dict(epoch=epoch+1, loss=total/(step+1), seconds=time.time()-started, validation=chosen)
        history.append(record); print(json.dumps(record), flush=True)
        quality = chosen['recall'] if acceptable else -chosen['false_positive_rate']
        if quality > best:
            best = quality; model.save_pretrained(out/'checkpoint'); tokenizer.save_pretrained(out/'checkpoint')
            (out/'selected.json').write_text(json.dumps(record, indent=2))
    model = BertForSequenceClassification.from_pretrained(out/'checkpoint', attn_implementation='eager').to(device)
    selected = json.loads((out/'selected.json').read_text())
    scores = predict(splits['test']); y = labels[splits['test']].numpy()
    result = dict(cleaning=cleaning, history=history, selected=selected, test=metrics(y, scores, selected['validation']['threshold']), data_sha256=hashlib.sha256(Path(args.data).read_bytes()).hexdigest(), max_length=args.length, parameters=sum(p.numel() for p in model.parameters()))
    (out/'metrics.json').write_text(json.dumps(result, indent=2))
    (out/'test-predictions.json').write_text(json.dumps([dict(rows[int(i)], probability=float(p)) for i,p in zip(splits['test'],scores)],ensure_ascii=False))
    print(json.dumps(dict(final_test=result['test'])), flush=True)


if __name__ == '__main__':
    main()
