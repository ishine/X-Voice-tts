#!/usr/bin/env bash
set -euo pipefail

ESPEAK_NG_COMMIT="b0b605c8a80f76c4c19e18033c6780c3cc4afc5b"
BUILD_DIR=$(mktemp -d /tmp/espeak-ng-build-XXXXXX)
CORES=$(nproc)

trap 'rm -rf "$BUILD_DIR"' EXIT

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run with sudo: sudo bash src/x_voice/prepare_ipa.sh" >&2
    exit 1
fi

echo "Installing build dependencies"
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y build-essential cmake git pkg-config
elif command -v yum >/dev/null 2>&1; then
    yum groupinstall -y "Development Tools"
    yum install -y cmake git pkgconfig
fi

if command -v dpkg-architecture >/dev/null 2>&1; then
    MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
else
    MULTIARCH=$(gcc -dumpmachine)
fi

echo "Building Espeak-NG commit $ESPEAK_NG_COMMIT"
git clone https://github.com/espeak-ng/espeak-ng.git "$BUILD_DIR/espeak-ng"
git -C "$BUILD_DIR/espeak-ng" checkout --detach "$ESPEAK_NG_COMMIT"

cmake -S "$BUILD_DIR/espeak-ng" -B "$BUILD_DIR/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR="lib/$MULTIARCH" \
    -DBUILD_SHARED_LIBS=ON \
    -DENABLE_TESTS=OFF
cmake --build "$BUILD_DIR/build" -j"$CORES"

echo "Removing conflicting Espeak-NG libraries and data"
for dir in /usr/local/lib /usr/lib "/usr/lib/$MULTIARCH" /root/.local/lib; do
    [ -d "$dir" ] || continue
    rm -f "$dir"/libespeak-ng.so*
done

if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [ -n "$USER_HOME" ] && [ -d "$USER_HOME/.local/lib" ]; then
        rm -f "$USER_HOME/.local/lib"/libespeak-ng.so*
    fi
fi

rm -rf /usr/share/espeak-ng-data \
       /usr/local/share/espeak-ng-data \
       /espeak-ng/share/espeak-ng-data

cmake --install "$BUILD_DIR/build"
ldconfig

echo "Verification"
unset PHONEMIZER_ESPEAK_LIBRARY
unset PHONEMIZER_ESPEAK_DATA_PATH
espeak-ng --version
python src/x_voice/train/datasets/test_ipav6.py --text "Hello world." --language en
# ipa_text: h|ə|l|ˈoʊ w|ˈɜː|l|d .
python src/x_voice/train/datasets/test_ipav6.py --text "안녕, 세상." --language ko
# ipa_text: iʲ|ˈɯ|ŋ|ɐ|n|n|j|ˌʌ|ŋ , s|e|s|ˈɐ|ŋ .
