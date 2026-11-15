# Local promotional-intent model

The shipping checkpoint is a fine-tuned MiniRBT H256 transformer, not a keyword list. `../Resources/RGAdModelSources.json` pins base weights, public source revisions, input digests, selection criteria and measured limitations. Only the base model is declared Apache-2.0; do not attribute that license to the public training corpora. Raw corpora, checkpoints, real messages and reports belong in ignored `build-input/` and are not distributed here.

## Training and evaluation

Use Python 3.11 and `requirements.txt` in an isolated environment. Scripts perform no network downloads. Obtain the pinned base and public files separately, review their terms, and provide explicit local paths.

1. `prepare-data.py --sniper INPUT.csv --olivi INPUT.csv --examples domain-examples.json --output build-input/ad-model-data` extracts only eligible text/label pairs. It drops account fields and creates authored simplified/traditional examples. The published combined input contained 53,762 rows.
2. `train.py --data build-input/ad-model-data/combined.csv --extra stages/base-authored.jsonl --base BASE_MODEL --output build-input/ad-model-base --epochs 6` deduplicates and groups near-duplicate text before making train/validation/test splits. Authored additions are training-only. The shipped base-stage run used 33,529 training, 7,003 validation and 6,663 test rows.
3. `adapt.py --source build-input/ad-model-base --examples stages/short-label-examples.json --output build-input/ad-model-short --epochs 4` adapts upper encoder layers using authored short-label/normal-content contrasts and training-only replay. The stage file reconstructs normalized authored inputs from the recorded run; it is not collected channel text.
4. `adapt.py --source build-input/ad-model-short --examples domain-examples.json --domain-validation domain-validation.json --output build-input/ad-model-context --epochs 4` adds full promotional cards, everyday-payment and news counterexamples. This stage excludes earlier authored rows from replay, then adds the current authored set. Domain validation is **authored checkpoint-selection material**, never training or an unseen test. Selection still requires the public-validation precision/false-positive constraints.
5. `export.py --training build-input/ad-model-context --output build-input/ad-model-export` converts the learned encoder and head to FP16-weight Core ML, writes the vocabulary/manifest and compares 100 conversion vectors with PyTorch. Copy an accepted artifact into Resources only after the native checks below.

MPS training is seeded but not guaranteed bit-for-bit deterministic. Use the bundled SHA-256 for the exact shipping checkpoint. `stages/base-authored.jsonl` contains only the recorded authored base inputs, not the public corpus. The original base split had 357 authored rows; the short-label adaptation had 520; the final adaptation had 614. Traditional variants count as training rows, not independent collected examples.

The strict final threshold is 0.996. On the noisy public spam test, precision was 98.44%, recall 40.83%, false-positive rate 0.67% (TP 1,385; FP 22; FN 2,007; TN 3,249). This is **not** app accuracy or a claim to remove 98% of channel ads. Final authored domain validation had 30/30 normal cases retained and 23/25 promotions detected. The external bot's development examples still expose missed abbreviated/obfuscated ads.

## Native integration acceptance

Run `swift test --package-path Regram/RGAdFilter` and `python3 Regram/RGAdFilter/Tools/run-bridge-checks.py`. `Tools/run-semantic-checks.py --resources MODEL_DIR --fixtures FIXTURE_DIR --output build-input/ad-model-checks` executes the production tokenizer, Core ML classifier, policy and range projection. The same `SemanticHarness.swift` runs on a physical iPhone. Fixtures and reports can include real messages and must remain ignored.

Verify full message outcomes, retained text/entities, independent buttons, quoted promotion cards, original recovery, model resources in the final IPA, and real device latency. Conversion checks compare probability values, not just argmax labels. Score-call timings include cache hits; use per-message `predictionMilliseconds` for the complete observed pipeline and do not describe them as all-uncached benchmarks.

The native layer limits semantic inference to Chinese, requires paragraph agreement for sentence cuts, protects code and uncertain content, and uses heading/call-to-action context for long promotional cards. Images/video pixels, unsupported languages, coded language and advertorial ambiguity remain limitations. No automatic self-training from guessed labels, raw-message upload, or network model download occurs.
