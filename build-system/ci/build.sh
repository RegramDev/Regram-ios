#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# Reference package builds intentionally use the same Xcode generation as local b34582.
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
xcode_details="$(xcodebuild -version)"
xcode_number="$(printf '%s\n' "$xcode_details" | sed -n 's/^Xcode //p')"
xcode_build="$(printf '%s\n' "$xcode_details" | sed -n 's/^Build version //p')"
if [[ "$xcode_number" != 27.* ]]; then
  echo 'This workflow requires the xcode-27 runner with Xcode 27.' >&2
  exit 1
fi
xcode_selector="$xcode_number"
[[ "$xcode_number" == *.*.* ]] || xcode_selector="$xcode_number.0"
xcode_selector="$xcode_selector.$xcode_build"

mkdir -p build-input/ci build/artifacts
read -r bazel_version bazel_sha < <(python3 - <<'PY'
import json
version, checksum = json.load(open('versions.json'))['bazel'].split(':')
print(version, checksum)
PY
)
bazel_path="$PWD/build-input/bazel-$bazel_version-darwin-arm64"
if [[ ! -f "$bazel_path" ]]; then
  curl --fail --location --retry 3 "https://github.com/bazelbuild/bazel/releases/download/$bazel_version/bazel-$bazel_version-darwin-arm64" -o "$bazel_path"
fi
printf '%s  %s\n' "$bazel_sha" "$bazel_path" | shasum -a 256 --check --status
chmod +x "$bazel_path"

python3 build-system/ci/prepare.py --config build-input/ci/configuration.json \
  --output build-input/configuration-repository --bazel "$bazel_path"

git -C build-system/bazel-rules/rules_apple apply --check ../../patches/rules_apple-local.patch
git -C build-system/bazel-rules/rules_apple apply ../../patches/rules_apple-local.patch

build_number="${REGRAM_BUILD_NUMBER:-$(($(git rev-list --count HEAD) + $(cat build_number_offset)))}"
# Limit parallel compilation for the standard 7 GB arm64 runner; keep cached build configuration
# and all six extensions. No simulator or personal signing identity is needed.
"$bazel_path" --nohome_rc --host_jvm_args=-Xmx1536m build //Telegram:Regram \
  --ios_signing_cert_name=- --xcode_version="$xcode_selector" \
  --action_env="XCODE_VERSION_OVERRIDE=$DEVELOPER_DIR" \
  --define="buildNumber=$build_number" -c opt --ios_multi_cpus=arm64 \
  --watchos_cpus=armv7k,arm64_32 --apple_generate_dsym --output_groups=+dsyms \
  --features=swift.use_global_module_cache --features=swift.opt_uses_wmo \
  --features=swift.opt_uses_osize --@rules_rust//rust/settings:lto=fat \
  --features=dead_strip --objc_enable_binary_stripping --remote_cache_async \
  --jobs=2 --local_resources=memory=4096 --local_resources=cpu=2 \
  --@build_bazel_rules_swift//swift:copt=-num-threads --@build_bazel_rules_swift//swift:copt=2 \
  --disk_cache="$PWD/build-input/ci-cache" \
  --//Telegram:disableExtensions=false --//Regram/RGAppGroupIdentifier:sandboxOnly=false \
  --//Regram/RGSimpleSettings:mediaLoadingExperimentDefault=true

python3 build-system/ci/package.py --ipa bazel-bin/Telegram/Regram.ipa \
  --symbols bazel-bin/Telegram --output build/artifacts --build-number "$build_number"
