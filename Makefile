APP_NAME := ThermoCamUVC
BUILD_DIR := .build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
EXECUTABLE := $(MACOS_DIR)/$(APP_NAME)
SOURCES := $(shell find Sources -name '*.swift' | sort)
SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)
ARCH := $(shell uname -m)
DEPLOYMENT_TARGET := 15.0
DIST_DIR := dist
PACKAGE_NAME := $(APP_NAME)-macos-$(ARCH)-adhoc.zip
PACKAGE_ZIP := $(DIST_DIR)/$(PACKAGE_NAME)

SWIFT_FLAGS := \
	-sdk $(SDKROOT) \
	-target $(ARCH)-apple-macosx$(DEPLOYMENT_TARGET) \
	-parse-as-library \
	-framework AppKit \
	-framework AVFoundation \
	-framework CoreImage \
	-framework CoreMedia \
	-framework CoreVideo \
	-framework ImageIO \
	-framework IOKit \
	-framework Metal \
	-framework QuartzCore \
	-framework SwiftUI \
	-framework UniformTypeIdentifiers

.PHONY: build run verify package clean clean-dist

build: $(EXECUTABLE)

$(EXECUTABLE): $(SOURCES) Info.plist ThermoCamUVC.entitlements
	mkdir -p "$(MACOS_DIR)"
	cp Info.plist "$(CONTENTS_DIR)/Info.plist"
	swiftc $(SWIFT_FLAGS) $(SOURCES) -o "$(EXECUTABLE)"
	codesign --force --sign - --entitlements ThermoCamUVC.entitlements "$(APP_BUNDLE)"

run: build
	open "$(APP_BUNDLE)"

verify: build
	plutil -lint "$(CONTENTS_DIR)/Info.plist"
	codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"
	codesign -d --entitlements :- "$(APP_BUNDLE)" >/dev/null 2>&1

package: build verify
	rm -rf "$(DIST_DIR)"
	mkdir -p "$(DIST_DIR)"
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(PACKAGE_ZIP)"
	(cd "$(DIST_DIR)" && shasum -a 256 "$(PACKAGE_NAME)" > SHA256SUMS.txt)

clean:
	rm -rf "$(BUILD_DIR)"

clean-dist:
	rm -rf "$(DIST_DIR)"
