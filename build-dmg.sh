#!/bin/bash
set -e

APP_NAME="MSG File Viewer"
BUNDLE_ID="com.abhishekdadhich.MSGFileViewer"
EXECUTABLE_NAME="MSGFileViewer"
DMG_NAME="MSGFileViewer"
VERSION="1.0.0"

echo "🔨 Building release binary..."
swift build -c release

echo "📦 Creating app bundle..."
APP_DIR=".build/release/${APP_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy the executable
cp ".build/release/${EXECUTABLE_NAME}" "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"

# Create Info.plist
cat > "${APP_DIR}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Outlook Message</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>msg</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.microsoft.outlook-message</string>
            </array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
            <key>UTTypeDescription</key>
            <string>Microsoft Outlook Message</string>
            <key>UTTypeIdentifier</key>
            <string>com.microsoft.outlook-message</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>msg</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
EOF

# Copy app icon
if [ -f "Sources/MSGFileViewer/AppIcon.icns" ]; then
    cp "Sources/MSGFileViewer/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

# Create PkgInfo
echo -n "APPL????" > "${APP_DIR}/Contents/PkgInfo"

echo "💿 Creating DMG..."
DMG_DIR=".build/dmg"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_DIR" "$DMG_DIR/"

# Create a symlink to /Applications for easy drag-install
ln -s /Applications "$DMG_DIR/Applications"

# Create the DMG
DMG_PATH=".build/${DMG_NAME}-${VERSION}.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_PATH"

echo ""
echo "✅ Done! DMG created at: $DMG_PATH"
echo "   App bundle: $APP_DIR"
echo ""
echo "To install: Open the DMG and drag '${APP_NAME}' to Applications."
