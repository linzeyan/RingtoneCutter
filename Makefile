# RingtoneCutter — SwiftUI iOS app
#
# RingtoneCutter.xcodeproj is generated from project.yml via xcodegen — it is not
# hand-edited and not committed. Edit project.yml, then `make generate`.

PROJECT   := RingtoneCutter.xcodeproj
SCHEME    := RingtoneCutter
CONFIGURATION := Debug
DERIVED   := build
APP       := $(DERIVED)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(SCHEME).app
BUNDLE_ID := com.zeyanlin.ringtonecutter
SIMULATOR ?= iPhone 17

# The paired iPhone XR (iOS 18.7), by UDID from `xcrun xctrace list devices`.
DEVICE_ID ?= 00008020-00192DA82128002E
DEVICE_APP := $(DERIVED)/Build/Products/$(CONFIGURATION)-iphoneos/$(SCHEME).app

ARCHIVE   := $(DERIVED)/$(SCHEME).xcarchive
EXPORT    := $(DERIVED)/export

# Store screenshots: `device type=output folder`, comma separated. Each runs on a
# dedicated iOS 26.5 simulator (scripts/shot_simulator.sh), so the shots show the
# "Use as Ringtone" share action. 6.9" is the size App Store Connect requires for
# an iPhone-only app; 6.5" is uploaded too because a scaled-down 6.9" is not what
# that screen actually shows.
SHOT_DEVICES ?= iPhone 17 Pro Max=iphone-6.9,iPhone 11 Pro Max=iphone-6.5
SHOT_LANGS   ?= zh-Hant en
SHOTS        ?= screenshots
STATUS_BAR   ?= --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
	--cellularMode active --cellularBars 4 --operatorName '' \
	--batteryState discharging --batteryLevel 100
DEMO         := $(DERIVED)/demo

.DEFAULT_GOAL := help
.PHONY: help setup generate icon build test run run-device open clean demo-audio screenshots shots-device release archive ipa

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## install xcodegen (if needed) and generate the Xcode project
	@which xcodegen > /dev/null || brew install xcodegen
	$(MAKE) generate

generate: ## regenerate RingtoneCutter.xcodeproj from project.yml (source of truth)
	xcodegen generate

icon: ## Render design/AppIcon.svg into the asset catalog (needs rsvg-convert)
	rsvg-convert -w 1024 -h 1024 design/AppIcon.svg \
		-o RingtoneCutter/Assets.xcassets/AppIcon.appiconset/AppIcon.png

clean: ## Remove build artifacts
	rm -rf $(DERIVED)

build: generate ## Compile the app for the simulator
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(DERIVED) build

test: generate ## Run unit tests
	xcodebuild test -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-only-testing:RingtoneCutterTests

run: build ## Build, then install & launch on the iPhone simulator
	@xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	open -a Simulator
	xcrun simctl install "$(SIMULATOR)" "$(APP)"
	xcrun simctl launch "$(SIMULATOR)" $(BUNDLE_ID)

run-device: generate ## Build, then install & launch on the connected iPhone
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination 'platform=iOS,id=$(DEVICE_ID)' \
		-derivedDataPath $(DERIVED) \
		-allowProvisioningUpdates \
		build
	xcrun devicectl device install app --device $(DEVICE_ID) "$(DEVICE_APP)"
	xcrun devicectl device process launch --device $(DEVICE_ID) --terminate-existing $(BUNDLE_ID)

open: generate ## Open the project in Xcode
	open $(PROJECT)

# --- App Store ---

demo-audio: ## Synthesize the demo track the screenshots load (needs ffmpeg)
	@# Made here rather than borrowed: the listing must not show anyone else's song.
	@# Sections of different loudness so the waveform reads as music: quiet intro,
	@# verse, chorus at 60-90 s (where the screenshots put the clip), break, verse,
	@# chorus, fade. Slow, mismatched swells keep neighbouring bars from levelling
	@# into a solid block once a bar covers a second of audio.
	@mkdir -p "$(DEMO)"
	ffmpeg -y -loglevel error -f lavfi -i "aevalsrc='\
	if(lt(t,20),0.15,if(lt(t,60),0.35,if(lt(t,90),0.8,if(lt(t,100),0.1,if(lt(t,140),0.4,if(lt(t,170),0.85,0.03*(180-t)))))))\
	*(0.5+0.3*sin(2*PI*0.31*t)*sin(2*PI*0.13*t+1)+0.2*abs(sin(2*PI*0.83*t)))\
	*(0.5*sin(2*PI*220*t)+0.3*sin(2*PI*277.2*t)+0.2*sin(2*PI*329.6*t))':s=44100:d=180" \
		-c:a aac -b:a 96k "$(DEMO)/demo.m4a"
	cp "$(DEMO)/demo.m4a" "$(DEMO)/夏日午後.m4a"
	cp "$(DEMO)/demo.m4a" "$(DEMO)/Summer Afternoon.m4a"

screenshots: generate demo-audio ## Capture App Store screenshots (every language × every size in SHOT_DEVICES)
	@for lang in $(SHOT_LANGS); do \
		( entries='$(SHOT_DEVICES)'; IFS=','; \
		for entry in $$entries; do \
			$(MAKE) --no-print-directory shots-device \
				DEVICE="$${entry%%=*}" LANG_ID=$$lang OUT="$(SHOTS)/$$lang/$${entry##*=}" || exit 1; \
		done ) || exit 1; \
	done
	@echo "screenshots → $(SHOTS)/"

shots-device:
	@rm -rf "$(DERIVED)/shots.xcresult" "$(OUT)"
	@mkdir -p "$(OUT)"
	@# Booted here rather than by xcodebuild: the system language has to be set
	@# before boot, and the status bar can only be overridden on a running simulator.
	@udid=$$(bash scripts/shot_simulator.sh "$(DEVICE)" $(LANG_ID)) || exit 1; \
	xcrun simctl status_bar "$$udid" override $(STATUS_BAR) || exit 1; \
	demo="$(CURDIR)/$(DEMO)/$$( [ "$(LANG_ID)" = en ] && echo 'Summer Afternoon' || echo '夏日午後' ).m4a"; \
	echo "→ $(DEVICE) [$(LANG_ID)] $$udid"; \
	TEST_RUNNER_RINGTONE_SCREENSHOTS=1 \
	TEST_RUNNER_RINGTONE_SHOT_LANG=$(LANG_ID) \
	TEST_RUNNER_RINGTONE_DEMO_FILE="$$demo" \
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED) \
		-resultBundlePath "$(DERIVED)/shots.xcresult" \
		-destination "id=$$udid" \
		-only-testing:RingtoneCutterUITests/ScreenshotTests \
		> "$(DERIVED)/shots.log" 2>&1 \
		|| { tail -40 "$(DERIVED)/shots.log"; exit 1; }
	@# Attachments come out under generated filenames; manifest.json carries the
	@# name the test gave each one.
	@xcrun xcresulttool export attachments \
		--path "$(DERIVED)/shots.xcresult" --output-path "$(OUT)" >/dev/null
	@python3 scripts/name_screenshots.py "$(OUT)"

release: archive ipa ## Archive + export an uploadable .ipa

archive: generate ## Archive a signed Release build (auto signing)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE) \
		-allowProvisioningUpdates \
		archive

ipa: ## Export an uploadable .ipa from the archive (run `make archive` first)
	@# Force the system rsync first: a Homebrew rsync in PATH breaks the IPA
	@# packaging step with "Copy failed" (extended-attributes incompatibility).
	PATH="/usr/bin:/bin:/usr/sbin:/sbin:$$PATH" xcodebuild -exportArchive \
		-archivePath $(ARCHIVE) \
		-exportOptionsPlist exportOptions.plist \
		-exportPath $(EXPORT) \
		-allowProvisioningUpdates
	@echo "IPA → $(EXPORT)/$(SCHEME).ipa  (upload via Transporter)"
