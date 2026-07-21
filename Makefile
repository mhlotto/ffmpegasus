SWIFT := swift
APP := FFMpegasus
CLANG_MODULE_CACHE_PATH ?= $(CURDIR)/.build/clang-module-cache
export CLANG_MODULE_CACHE_PATH

.PHONY: build run test clean fixtures fixtures-validate fixtures-clean ui-test xcui-test

build:
	$(SWIFT) build

run:
	$(SWIFT) run $(APP)

test:
	$(SWIFT) test

clean:
	$(SWIFT) package clean

fixtures:
	scripts/fixtures.sh generate

fixtures-validate:
	scripts/fixtures.sh validate

fixtures-clean:
	scripts/fixtures.sh clean

ui-test: fixtures
	$(SWIFT) build
	FFMPEGASUS_RUN_GUI_TESTS=1 $(SWIFT) test --filter FFMpegasusGUITests

xcui-test: fixtures
	xcodebuild test \
		-project FFMpegasusXCUITests.xcodeproj \
		-scheme FFMpegasusXCUITests \
		-destination 'platform=macOS' \
		-derivedDataPath .build/xcui-derived \
		-parallel-testing-enabled NO
