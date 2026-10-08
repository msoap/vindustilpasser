APP := vindustilpasser
BUNDLE := build/$(APP).app
BUNDLE_ID := com.local.vindustilpasser
APP_VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
DMG := build/$(APP)-$(APP_VERSION).dmg

.PHONY: build build-unsigned assemble-app clean deploy build-dmg test setup-signing new-version inc-patch-version inc-minor-version inc-major-version

new-version:
	@./scripts/update-version.sh set

inc-patch-version:
	@./scripts/update-version.sh patch

inc-minor-version:
	@./scripts/update-version.sh minor

inc-major-version:
	@./scripts/update-version.sh major

setup-signing:
	./scripts/setup-local-signing.sh

test:
	mkdir -p build
	swiftc -swift-version 5 -parse-as-library -plugin-path /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing -F /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
		-Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
		-o build/vindustilpasserTests \
		Sources/vindustilpasser/Geometry/*.swift Sources/vindustilpasser/HotKeys/HotKey.swift \
		Sources/vindustilpasser/HotKeys/HotKeyRecorderView.swift Sources/vindustilpasser/Accessibility/WindowFrameApplication.swift \
		Sources/vindustilpasser/Preferences/PresetTableView.swift \
		Sources/vindustilpasser/Settings/*.swift Tests/vindustilpasserTests/*.swift
	DYLD_LIBRARY_PATH=/Library/Developer/CommandLineTools/Library/Developer/usr/lib build/vindustilpasserTests

assemble-app:
	swift build -c release --build-system native --product $(APP)
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$$(swift build -c release --build-system native --show-bin-path)/$(APP)" "$(BUNDLE)/Contents/MacOS/$(APP)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/"; fi

build-unsigned: assemble-app
	codesign --force --sign - -i "$(BUNDLE_ID)" "$(BUNDLE)"
	codesign --verify --strict --verbose=2 "$(BUNDLE)"
	@echo "Built $(BUNDLE) with ad-hoc signature (no Keychain identity)"

build: assemble-app
	./scripts/sign-app.sh "$(BUNDLE)" "$(BUNDLE_ID)"
	@echo "Built $(BUNDLE) (bundle ID: $(BUNDLE_ID))"

clean:
	rm -rf build .build
	@echo 'Preserved .local-signing and Keychain identity'

deploy: build
	@set -eu; if [ -n "$${DEPLOY_DIR:-}" ]; then dest="$$DEPLOY_DIR"; elif [ -d "$(HOME)/Applications" ]; then dest="$(HOME)/Applications"; else dest=/Applications; fi; \
	if [ -w "$$dest" ]; then rm -rf "$$dest/$(APP).app"; ditto "$(BUNDLE)" "$$dest/$(APP).app"; else sudo rm -rf "$$dest/$(APP).app"; sudo ditto "$(BUNDLE)" "$$dest/$(APP).app"; fi; \
	echo "Deployed $$dest/$(APP).app"

build-dmg:
	swift build -c release --build-system native --product $(APP)
	rm -rf build/dmg-stage "$(DMG)"
	mkdir -p "build/dmg-stage/$(APP).app/Contents/MacOS" "build/dmg-stage/$(APP).app/Contents/Resources"
	cp "$$(swift build -c release --build-system native --show-bin-path)/$(APP)" "build/dmg-stage/$(APP).app/Contents/MacOS/$(APP)"
	cp Resources/Info.plist "build/dmg-stage/$(APP).app/Contents/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "build/dmg-stage/$(APP).app/Contents/Resources/"; fi
	codesign --force --sign - -i "$(BUNDLE_ID)" "build/dmg-stage/$(APP).app"
	codesign --verify --strict --verbose=2 "build/dmg-stage/$(APP).app"
	hdiutil create -volname "$(APP)" -srcfolder build/dmg-stage -ov -format UDZO "$(DMG)"
	@echo 'Built ad-hoc signed $(DMG)'
