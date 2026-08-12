#!/bin/bash
# Builds an unsigned Pachyderm.ipa (or .tipa) into ./build.
#
#   --debug        build the Debug configuration and skip stripping
#   --clean        delete ./build (including DerivedData) first
#   --tipa         package as .tipa instead of .ipa
#   --scriptdebug  set -x, don't prettify xcodebuild output

set -euo pipefail
if [[ $* == *--scriptdebug* ]]; then
    set -x
fi

cd "$(dirname "$0")"

WORKING_LOCATION="$(pwd)"
APPLICATION_NAME=Pachyderm
PLATFORM=iOS
SDK=iphoneos
if [[ $* == *--debug* ]]; then
    TARGET=Debug
else
    TARGET=Release
fi

# xcbeautify/xcpretty
if [[ $* == *--scriptdebug* ]]; then
    XCBEAUTIFY="cat"
elif command -v xcbeautify > /dev/null; then
    XCBEAUTIFY="xcbeautify --disable-logging"
elif command -v xcpretty > /dev/null; then
    XCBEAUTIFY="xcpretty"
else
    XCBEAUTIFY="cat"
fi

if [[ $* == *--clean* ]]; then
    echo "[*] Deleting build folder..."
    rm -rf "build"
else
    echo "[*] Deleting previous packages..."
    rm -rf "build/$APPLICATION_NAME.ipa" \
           "build/$APPLICATION_NAME.tipa" \
           "build/$APPLICATION_NAME.app" \
           "build/Payload"
fi

echo "[*] Building $APPLICATION_NAME ($TARGET)..."

mkdir -p build
cd build

# `clean build` handles the incremental case; --clean above wipes DerivedData too.
xcodebuild -project "$WORKING_LOCATION/$APPLICATION_NAME.xcodeproj" \
    -scheme "$APPLICATION_NAME" \
    -configuration "$TARGET" \
    -derivedDataPath "$WORKING_LOCATION/build/DerivedDataApp" \
    -destination "generic/platform=$PLATFORM" \
    clean build \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED="NO" \
    | $XCBEAUTIFY

DD_APP_PATH="$WORKING_LOCATION/build/DerivedDataApp/Build/Products/$TARGET-$SDK/$APPLICATION_NAME.app"
TARGET_APP="$WORKING_LOCATION/build/$APPLICATION_NAME.app"
cp -r "$DD_APP_PATH" "$TARGET_APP"

echo "[*] Removing code signature"
codesign --remove-signature "$TARGET_APP" || true
rm -rf "$TARGET_APP/_CodeSignature" "$TARGET_APP/embedded.mobileprovision"

echo "[*] Packaging..."
mkdir -p Payload
cp -r "$APPLICATION_NAME.app" "Payload/$APPLICATION_NAME.app"

if [[ $* != *--debug* ]]; then
    strip "Payload/$APPLICATION_NAME.app/$APPLICATION_NAME"
fi

if [[ $* == *--scriptdebug* ]]; then
    ZIP_ARGS="-rv"
else
    ZIP_ARGS="-r"
fi

if [[ $* == *--tipa* ]]; then
    zip $ZIP_ARGS "$APPLICATION_NAME.tipa" Payload
else
    zip $ZIP_ARGS "$APPLICATION_NAME.ipa" Payload
fi

rm -rf "$APPLICATION_NAME.app" Payload

echo "[*] Done."
