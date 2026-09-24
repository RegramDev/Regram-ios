#!/bin/sh

set -e
set -x

ARCH="$1"

SOURCE_DIR="$2"
BUILD_DIR=$(echo "$(cd "$(dirname "$3")"; pwd -P)/$(basename "$3")")
OPENSSL_DIR="$4"

if [ -n "${DEVELOPER_DIR:-}" ]; then
  SELECTED_DEVELOPER_DIR="$DEVELOPER_DIR"
elif [ -n "${XCODE_VERSION_OVERRIDE:-}" ]; then
  case "$XCODE_VERSION_OVERRIDE" in
    /*)
      if [ -d "$XCODE_VERSION_OVERRIDE/Contents/Developer" ]; then
        SELECTED_DEVELOPER_DIR="$XCODE_VERSION_OVERRIDE/Contents/Developer"
      elif [ -d "$XCODE_VERSION_OVERRIDE" ]; then
        SELECTED_DEVELOPER_DIR="$XCODE_VERSION_OVERRIDE"
      else
        echo "Invalid XCODE_VERSION_OVERRIDE path: $XCODE_VERSION_OVERRIDE" >&2
        exit 1
      fi
      ;;
    *)
      SELECTED_DEVELOPER_DIR="$(xcode-select -p)"
      ;;
  esac
else
  SELECTED_DEVELOPER_DIR="$(xcode-select -p)"
fi

if [ ! -d "$SELECTED_DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain" ]; then
  echo "Selected developer directory does not contain the Xcode default toolchain: $SELECTED_DEVELOPER_DIR" >&2
  exit 1
fi

export DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR"
MACOS_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"
HOST_CC="$(xcrun --sdk macosx --find clang)"
HOST_CXX="$(xcrun --sdk macosx --find clang++)"

openssl_crypto_library="${OPENSSL_DIR}/lib/libcrypto.a"
options=""
options="$options -DOPENSSL_FOUND=1"
options="$options -DOPENSSL_CRYPTO_LIBRARY=${openssl_crypto_library}"
options="$options -DOPENSSL_INCLUDE_DIR=${OPENSSL_DIR}/src/include"
options="$options -DCMAKE_BUILD_TYPE=Release"
options="$options -DIOS_DEPLOYMENT_TARGET=13.0"

cd "$BUILD_DIR"

# Generate source files
mkdir native-build
cd native-build
SDKROOT="$MACOS_SYSROOT" cmake \
  -DTD_GENERATE_SOURCE_FILES=ON \
  -DCMAKE_OSX_SYSROOT="$MACOS_SYSROOT" \
  -DCMAKE_C_COMPILER="$HOST_CC" \
  -DCMAKE_CXX_COMPILER="$HOST_CXX" \
  ../td
SDKROOT="$MACOS_SYSROOT" cmake --build . -- -j$(sysctl -n hw.ncpu)
cd ..

if [ "$ARCH" = "arm64" ]; then
  IOS_PLATFORMDIR="$SELECTED_DEVELOPER_DIR/Platforms/iPhoneOS.platform"
  IOS_SYSROOT=($IOS_PLATFORMDIR/Developer/SDKs/iPhoneOS*.sdk)
  export CFLAGS="-arch arm64 --target=arm64-apple-ios13.0 -miphoneos-version-min=13.0 -w"
elif [ "$ARCH" = "sim_arm64" ]; then
  IOS_PLATFORMDIR="$SELECTED_DEVELOPER_DIR/Platforms/iPhoneSimulator.platform"
  IOS_SYSROOT=($IOS_PLATFORMDIR/Developer/SDKs/iPhoneSimulator*.sdk)
  export CFLAGS="-arch arm64 --target=arm64-apple-ios13.0-simulator -miphonesimulator-version-min=13.0 -w"
elif [ "$ARCH" = "macos_arm64" ]; then
  IOS_PLATFORMDIR="$SELECTED_DEVELOPER_DIR/Platforms/MacOSX.platform"
  IOS_SYSROOT=($IOS_PLATFORMDIR/Developer/SDKs/MacOSX*.sdk)
  export CFLAGS="-arch arm64 --target=arm64-apple-macosx14.0 -mmacosx-version-min=14.0 -w"
else
  echo "Unsupported architecture $ARCH"
  exit 1
fi
export CXXFLAGS="$CFLAGS"

# Common build steps
mkdir build
cd build

touch toolchain.cmake
echo "set(CMAKE_SYSTEM_NAME Darwin)" >> toolchain.cmake
echo "set(CMAKE_SYSTEM_PROCESSOR aarch64)" >> toolchain.cmake
echo "set(CMAKE_C_COMPILER $(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang)" >> toolchain.cmake

cmake -G"Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake -DCMAKE_OSX_SYSROOT=${IOS_SYSROOT[0]} ../td $options
make tde2e -j$(sysctl -n hw.ncpu)
