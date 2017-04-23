#!/bin/bash

# Build synth
cd synth
cargo build --release --target=x86_64-apple-darwin
cd ..

# Make the bundle folder
mkdir -p "Oidos.vst/Contents/MacOS"

# Create the PkgInfo
echo "BNDL????" > "Oidos.vst/Contents/PkgInfo"

#build the Info.Plist
echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>English</string>

    <key>CFBundleExecutable</key>
    <string>Oidos</string>

    <key>CFBundleGetInfoString</key>
    <string>vst</string>

    <key>CFBundleIconFile</key>
    <string></string>

    <key>CFBundleIdentifier</key>
    <string>com.rust-vst2.Oidos</string>

    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <key>CFBundleName</key>
    <string>Oidos</string>

    <key>CFBundlePackageType</key>
    <string>BNDL</string>

    <key>CFBundleVersion</key>
    <string>1.0</string>

    <key>CFBundleSignature</key>
    <string>5273</string>

    <key>CSResourcesFileMapped</key>
    <string></string>

</dict>
</plist>" > "Oidos.vst/Contents/Info.plist"

# move the provided library to the correct location
cp "synth/target/x86_64-apple-darwin/release/libOidos.dylib" "Oidos.vst/Contents/MacOS/Oidos"

# Build reverb
cd reverb
cargo build --release --target=x86_64-apple-darwin
cd ..

# Make the bundle folder
mkdir -p "OidosReverb.vst/Contents/MacOS"

# Create the PkgInfo
echo "BNDL????" > "OidosReverb.vst/Contents/PkgInfo"

#build the Info.Plist
echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>English</string>

    <key>CFBundleExecutable</key>
    <string>OidosReverb</string>

    <key>CFBundleGetInfoString</key>
    <string>vst</string>

    <key>CFBundleIconFile</key>
    <string></string>

    <key>CFBundleIdentifier</key>
    <string>com.rust-vst2.OidosReverb</string>

    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <key>CFBundleName</key>
    <string>OidosReverb</string>

    <key>CFBundlePackageType</key>
    <string>BNDL</string>

    <key>CFBundleVersion</key>
    <string>1.0</string>

    <key>CFBundleSignature</key>
    <string>5274</string>

    <key>CSResourcesFileMapped</key>
    <string></string>

</dict>
</plist>" > "OidosReverb.vst/Contents/Info.plist"

# move the provided library to the correct location
cp "reverb/target/x86_64-apple-darwin/release/libOidosReverb.dylib" "OidosReverb.vst/Contents/MacOS/OidosReverb"

echo "Created bundle Oidos.vst and OidosReverb.vst"
