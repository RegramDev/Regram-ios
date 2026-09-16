# Local submodule patches

`build-system/bazel-rules/rules_apple` carries uncommitted local changes that the build depends
on. A submodule only records a commit pointer, so those changes are invisible to a fresh
`git clone --recursive` — the checkout would be clean and the build would behave differently.
They are captured here instead.

Apply after cloning:

```sh
cd build-system/bazel-rules/rules_apple
git apply ../../patches/rules_apple-local.patch
```

Re-export after changing them:

```sh
cd build-system/bazel-rules/rules_apple && git diff > ../../patches/rules_apple-local.patch
```

The proper fix is a fork of rules_apple with these committed, pointed to by `.gitmodules`.
