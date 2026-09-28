# Regram Playground

Small app to quickly iterate on components testing without building an entire messenger.

## (Optional) Setup Codesigning

Create simple `codesigning/Playground.mobileprovision`. It is only required for non-simulator builds and can be skipped with `--disableProvisioningProfiles`.

## Generate Xcode project

Use the [main project setup](../../README.md), adding the `--target=Regram/Playground` parameter when generating the Xcode project.

## Run generated project on simulator

### From root

```shell
./Regram/Playground/launch_on_simulator.py
```

### From current directory

```shell
./launch_on_simulator.py
```
