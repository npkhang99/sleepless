SHELL := /bin/zsh

PROJECT := sleepless.xcodeproj
SCHEME := sleepless
CONFIGURATION := Release
DERIVED_DATA := build
APP_NAME := Sleepless
BUILD_PRODUCTS_DIR := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)
APP_BUNDLE := $(BUILD_PRODUCTS_DIR)/$(APP_NAME).app
DIST_DIR := dist
DMG_STAGING_DIR := $(DIST_DIR)/dmg
DMG_PATH := $(DIST_DIR)/$(APP_NAME).dmg

.PHONY: build package clean

build:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination 'platform=macOS' \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGNING_REQUIRED=NO \
		build

package: build
	rm -rf "$(DMG_STAGING_DIR)" "$(DMG_PATH)"
	mkdir -p "$(DMG_STAGING_DIR)"
	ditto "$(APP_BUNDLE)" "$(DMG_STAGING_DIR)/$(APP_NAME).app"
	ln -s /Applications "$(DMG_STAGING_DIR)/Applications"
	hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder "$(DMG_STAGING_DIR)" \
		-ov \
		-format UDZO \
		"$(DMG_PATH)"

clean:
	rm -rf "$(DERIVED_DATA)" "$(DIST_DIR)"
