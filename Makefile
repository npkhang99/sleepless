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
SPARKLE_FRAMEWORK := $(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework
SPARKLE_BIN := $(DERIVED_DATA)/SourcePackages/artifacts/sparkle/Sparkle/bin

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
RELEASE_DMG := $(DIST_DIR)/$(APP_NAME)-$(TAG).dmg
UPDATE_DIR := $(DIST_DIR)/update
APPCAST_PATH := $(DIST_DIR)/appcast.xml
RELEASE_URL := https://github.com/npkhang99/sleepless/releases/download/$(TAG)

.PHONY: build sign package appcast install release clean

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
	codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" \
		"$(SPARKLE_FRAMEWORK)/Versions/B/XPCServices/Installer.xpc"
	codesign --force --options runtime --preserve-metadata=entitlements \
		--sign "$(CODESIGN_IDENTITY)" \
		"$(SPARKLE_FRAMEWORK)/Versions/B/XPCServices/Downloader.xpc"
	codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" \
		"$(SPARKLE_FRAMEWORK)/Versions/B/Autoupdate"
	codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" \
		"$(SPARKLE_FRAMEWORK)/Versions/B/Updater.app"
	codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" \
		"$(SPARKLE_FRAMEWORK)"
	codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" "$(HELPER_BINARY)"
	codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" "$(APP_BUNDLE)"
	codesign --verify --deep --strict "$(APP_BUNDLE)"

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

appcast:
	@if [[ -z "$(TAG)" ]]; then \
		echo "usage: make appcast TAG=v0.0.7"; \
		exit 1; \
	fi
	$(MAKE) package
	@version=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
		"$(APP_BUNDLE)/Contents/Info.plist"); \
	if [[ "$(TAG)" != "v$$version" ]]; then \
		echo "TAG $(TAG) does not match app version v$$version"; \
		exit 1; \
	fi
	rm -rf "$(UPDATE_DIR)" "$(RELEASE_DMG)" "$(APPCAST_PATH)"
	mkdir -p "$(UPDATE_DIR)"
	cp "$(DMG_PATH)" "$(UPDATE_DIR)/$(notdir $(RELEASE_DMG))"
	@key_dir=$$(mktemp -d -t sleepless-sparkle-key); \
	key_path="$$key_dir/private-key"; \
	trap 'unlink "$$key_path"; rmdir "$$key_dir"' EXIT; \
	"$(SPARKLE_BIN)/generate_keys" -x "$$key_path"; \
	"$(SPARKLE_BIN)/generate_appcast" \
		--ed-key-file "$$key_path" \
		--download-url-prefix "$(RELEASE_URL)/" \
		--full-release-notes-url "https://github.com/npkhang99/sleepless/releases/tag/$(TAG)" \
		--maximum-versions 1 \
		"$(UPDATE_DIR)"
	mv "$(UPDATE_DIR)/appcast.xml" "$(APPCAST_PATH)"
	mv "$(UPDATE_DIR)/$(notdir $(RELEASE_DMG))" "$(RELEASE_DMG)"

# Publishes from this Mac so the assets keep the local signing identity.
# The GitHub Actions runner has no certificate and can only sign ad-hoc, which
# makes macOS ask for helper approval again after every update.
release: appcast
	@if [[ -z "$(TAG)" ]]; then \
		echo "usage: make release TAG=v0.0.7"; \
		exit 1; \
	fi
	@if gh release view "$(TAG)" >/dev/null 2>&1; then \
		echo "updating existing release $(TAG)"; \
		gh release upload "$(TAG)" "$(RELEASE_DMG)" "$(APPCAST_PATH)" --clobber; \
	else \
		echo "creating release $(TAG)"; \
		gh release create "$(TAG)" "$(RELEASE_DMG)" "$(APPCAST_PATH)" \
			--target "$$(git rev-parse HEAD)" \
			--title "$(RELEASE_TITLE)" \
			--generate-notes; \
	fi

clean:
	rm -rf "$(DERIVED_DATA)" "$(DIST_DIR)"
