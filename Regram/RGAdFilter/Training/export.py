#!/usr/bin/env python3
"""Export the trained transformer (including its learned classification head) to Core ML.

The fixed tensor contract is deliberately shared with the native WordPiece tokenizer.
Conversion parity is checked on held-out inputs; conversion never fits or tunes labels.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
import torch
import coremltools as ct
from coremltools.models.neural_network.quantization_utils import quantize_weights
from transformers import BertForSequenceClassification, BertTokenizer
from token_windows import native_windows

ap = argparse.ArgumentParser()
ap.add_argument('--training', required=True)
ap.add_argument('--output', required=True)
ap.add_argument('--weight-bits', type=int, choices=[16, 32], default=16)
args = ap.parse_args()
source, output = Path(args.training), Path(args.output)
output.mkdir(parents=True, exist_ok=True)
record = json.loads((source/'metrics.json').read_text())
length = record['max_length']
torch.set_num_threads(4)
model = BertForSequenceClassification.from_pretrained(source/'checkpoint', attn_implementation='eager').eval()
tokenizer = BertTokenizer.from_pretrained(source/'checkpoint')

class Classifier(torch.nn.Module):
    def __init__(self, model):
        super().__init__(); self.model = model
    def forward(self, input_ids, attention_mask):
        return torch.softmax(self.model(input_ids=input_ids, attention_mask=attention_mask).logits, dim=-1)

wrapper = Classifier(model).eval()
example = (torch.ones((1,length), dtype=torch.int32), torch.ones((1,length), dtype=torch.int32))
traced = torch.jit.trace(wrapper, example)
converted = ct.convert(traced, convert_to='neuralnetwork', minimum_deployment_target=ct.target.iOS14,
    inputs=[ct.TensorType(name='input_ids', shape=(1,length), dtype=np.int32), ct.TensorType(name='attention_mask', shape=(1,length), dtype=np.int32)],
    outputs=[ct.TensorType(name='probabilities')])
if args.weight_bits == 16:
    converted = quantize_weights(converted, nbits=16)
converted.author = 'Regram; MiniRBT encoder by HIT and iFLYTEK Research'
converted.short_description = 'Local Chinese Telegram promotional-segment classifier. Preserve uncertain content.'
converted.version = '1'
converted.license = 'MiniRBT base weights: Apache-2.0. See RGAdModelSources.json for training provenance.'
destination = output/'RGAdSemantic.mlmodel'
converted.save(destination)
native = ct.models.MLModel(str(destination), compute_units=ct.ComputeUnit.CPU_ONLY)
rows = json.loads((source/'split.json').read_text())['test'][:100]
max_error = 0
vectors = []
for row in rows:
    x = tokenizer(row['text'], padding='max_length', truncation=True, max_length=length, return_tensors='pt')
    with torch.no_grad():
        expected = wrapper(x['input_ids'].int(), x['attention_mask'].int()).numpy()
    actual = native.predict({'input_ids':x['input_ids'].numpy().astype(np.int32), 'attention_mask':x['attention_mask'].numpy().astype(np.int32)})['probabilities']
    max_error = max(max_error, float(np.abs(expected-actual).max()))
    vectors.append(dict(text=row['text'], ids=x['input_ids'][0].tolist(), windows=native_windows(tokenizer.encode(row['text'], add_special_tokens=False), length), probability=float(actual.reshape(-1)[1]), label=row['label']))
assert max_error < 0.01, max_error
(source/'conversion-vectors.json').write_text(json.dumps(vectors, ensure_ascii=False))
# Exercise full-window boundaries independently of the short probability probes.
window_vectors = []
for count in [0, 1, 125, 126, 127, 235, 236, 237, 896, 897, 1024, 1025]:
    text = '测' * count
    window_vectors.append(dict(text=text, windows=native_windows(tokenizer.encode(text, add_special_tokens=False), length)))
(source/'window-vectors.json').write_text(json.dumps(window_vectors, ensure_ascii=False))
(output/'RGAdVocabulary.txt').write_bytes((source/'checkpoint/vocab.txt').read_bytes())
manifest = dict(version=1, architecture='MiniRBT-H256-6L', sequenceLength=length,
    weightBits=args.weight_bits,
    threshold=record['selected']['validation']['threshold'], modelSHA256=hashlib.sha256(destination.read_bytes()).hexdigest(),
    vocabularySHA256=hashlib.sha256((output/'RGAdVocabulary.txt').read_bytes()).hexdigest(),
    labels=['content', 'promotion'], maxConversionError=max_error)
(output/'RGAdModel.json').write_text(json.dumps(manifest, indent=2))
print(json.dumps(manifest))
