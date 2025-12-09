#!/bin/bash

# 重新签名所有嵌入的 framework
# 解决 Xcode 14+ / iOS 16+ 签名验证失败问题

echo "Signing embedded frameworks..."

FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [ -d "$FRAMEWORKS_DIR" ]; then
    find "$FRAMEWORKS_DIR" -name '*.framework' -type d | while read FRAMEWORK; do
        echo "Signing: $FRAMEWORK"
        /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements --timestamp=none "$FRAMEWORK"
    done
fi

echo "Framework signing complete."
