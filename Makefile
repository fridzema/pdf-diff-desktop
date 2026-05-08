.PHONY: build-rust generate-bindings build-app test-rust test-swift test clean release

RUST_TARGET = aarch64-apple-darwin
RUST_LIB = rust-core/target/$(RUST_TARGET)/release/libpdf_diff_core.a
GENERATED_DIR = generated
XCODE_PROJECT = PdfDiffApp/PdfDiff.xcodeproj
SCHEME = PdfDiff
BUILD_DIR = build

# Set via environment: TEAM_ID=YOURTEAMID make release
TEAM_ID ?=

build-rust:
	cd rust-core && cargo build --release --target $(RUST_TARGET)

generate-bindings: build-rust
	cd rust-core && cargo run --bin uniffi-bindgen generate \
		--library target/$(RUST_TARGET)/release/libpdf_diff_core.dylib \
		-l swift \
		-o ../$(GENERATED_DIR)/

build-app: generate-bindings
	xcodebuild \
		-project $(XCODE_PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR)/ \
		ONLY_ACTIVE_ARCH=NO \
		ENABLE_HARDENED_RUNTIME=YES \
		$(if $(TEAM_ID),DEVELOPMENT_TEAM=$(TEAM_ID) CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual,CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual)

release: build-app
	@test -n "$(TEAM_ID)" || (echo "Error: set TEAM_ID=YOURTEAMID" && exit 1)
	ditto -c -k --keepParent $(BUILD_DIR)/Build/Products/Release/PdfDiff.app $(BUILD_DIR)/PdfDiff.zip
	xcrun notarytool submit $(BUILD_DIR)/PdfDiff.zip \
		--keychain-profile "pdfdiff-notarize" \
		--wait
	xcrun stapler staple $(BUILD_DIR)/Build/Products/Release/PdfDiff.app
	@echo "Verify: xcrun stapler validate $(BUILD_DIR)/Build/Products/Release/PdfDiff.app"

test-rust:
	cd rust-core && cargo test

test-swift:
	xcodebuild test -project $(XCODE_PROJECT) -scheme $(SCHEME)

test: test-rust test-swift

clean:
	cd rust-core && cargo clean
	rm -rf $(GENERATED_DIR)
	rm -rf $(BUILD_DIR)
