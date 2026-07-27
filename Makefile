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
HELPER_LABEL := com.curoa99.sleepless.helper.v2
HELPER_BINARY := $(APP_BUNDLE)/Contents/Resources/$(HELPER_LABEL)
INSTALL_PATH := /Applications/$(APP_NAME).app

# SMAppService refuses to register the helper unless the app bundle is signed,
# because the daemon plist must be sealed by the signature. Ad-hoc signing is
# enough for that, so CI machines without a certificate still produce a working
# build — the user just has to re-approve the helper after each update.
CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning | \
	awk '/Developer ID Application|Apple Development/ { print $$2; exit }')

ifeq ($(strip $(CODESIGN_IDENTITY)),)
CODESIGN_IDENTITY := -
endif

TAG ?=
RELEASE_TITLE ?= $(APP_NAME) $(TAG)
RELEASE_ZIP := $(DIST_DIR)/$(APP_NAME)-$(TAG).app.zip
RELEASE_DMG := $(DIST_DIR)/$(APP_NAME)-$(TAG).dmg

.PHONY: build sign package install release clean

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
	$(MAKE) sign

sign:
	codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" "$(HELPER_BINARY)"
	codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" "$(APP_BUNDLE)"
	codesign --verify --strict "$(APP_BUNDLE)"

install: build
	osascript -e 'tell application "$(APP_NAME)" to quit' 2>/dev/null || true
	sleep 1
	rm -rf "$(INSTALL_PATH)"
	ditto "$(APP_BUNDLE)" "$(INSTALL_PATH)"
	open -a "$(INSTALL_PATH)"

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

# Publishes from this Mac so the assets keep the local signing identity.
# The GitHub Actions runner has no certificate and can only sign ad-hoc, which
# makes macOS ask for helper approval again after every update.
release:
	@if [[ -z "$(TAG)" ]]; then \
		echo "usage: make release TAG=v0.0.4"; \
		exit 1; \
	fi
	$(MAKE) package
	rm -f "$(RELEASE_ZIP)" "$(RELEASE_DMG)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$(RELEASE_ZIP)"
	cp "$(DMG_PATH)" "$(RELEASE_DMG)"
	@if gh release view "$(TAG)" >/dev/null 2>&1; then \
		echo "updating existing release $(TAG)"; \
		gh release upload "$(TAG)" "$(RELEASE_ZIP)" "$(RELEASE_DMG)" --clobber; \
	else \
		echo "creating release $(TAG)"; \
		gh release create "$(TAG)" "$(RELEASE_ZIP)" "$(RELEASE_DMG)" \
			--target "$$(git rev-parse HEAD)" \
			--title "$(RELEASE_TITLE)" \
			--generate-notes; \
	fi

clean:
	rm -rf "$(DERIVED_DATA)" "$(DIST_DIR)"
