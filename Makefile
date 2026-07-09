.PHONY: help build-rust generate-bindings build-app build dev run test-rust test-swift test clean release

.DEFAULT_GOAL := help

RUST_TARGET = aarch64-apple-darwin
RUST_LIB = rust-core/target/$(RUST_TARGET)/release/libpdf_diff_core.a
GENERATED_DIR = generated
XCODE_PROJECT = PdfDiffApp/PdfDiff.xcodeproj
SCHEME = PdfDiff
BUILD_DIR = build

# Set via environment: TEAM_ID=YOURTEAMID make release
TEAM_ID ?=

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

build-rust: ## Build the Rust core (release, aarch64)
	cd rust-core && cargo build --release --target $(RUST_TARGET)

generate-bindings: build-rust ## Build Rust + regenerate UniFFI Swift bindings
	cd rust-core && cargo run --bin uniffi-bindgen generate \
		--library target/$(RUST_TARGET)/release/libpdf_diff_core.dylib \
		-l swift \
		-o ../$(GENERATED_DIR)/

build-app: generate-bindings ## Build the release .app
	xcodebuild \
		-project $(XCODE_PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR)/ \
		ONLY_ACTIVE_ARCH=NO \
		ENABLE_HARDENED_RUNTIME=YES \
		$(if $(TEAM_ID),DEVELOPMENT_TEAM=$(TEAM_ID) CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual,CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual)

build: build-app ## Build the release .app (alias for build-app)

dev: generate-bindings ## Build (Debug) and launch the app
	xcodebuild \
		-project $(XCODE_PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR)/ \
		$(if $(TEAM_ID),DEVELOPMENT_TEAM=$(TEAM_ID) CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual,CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual)
	open $(BUILD_DIR)/Build/Products/Debug/PdfDiff.app

run: ## Launch the last Debug build without rebuilding
	open $(BUILD_DIR)/Build/Products/Debug/PdfDiff.app

release: build-app ## Build, notarize and staple (needs TEAM_ID)
	@test -n "$(TEAM_ID)" || (echo "Error: set TEAM_ID=YOURTEAMID" && exit 1)
	ditto -c -k --keepParent $(BUILD_DIR)/Build/Products/Release/PdfDiff.app $(BUILD_DIR)/PdfDiff.zip
	xcrun notarytool submit $(BUILD_DIR)/PdfDiff.zip \
		--keychain-profile "pdfdiff-notarize" \
		--wait
	xcrun stapler staple $(BUILD_DIR)/Build/Products/Release/PdfDiff.app
	@echo "Verify: xcrun stapler validate $(BUILD_DIR)/Build/Products/Release/PdfDiff.app"

test-rust: ## Run the Rust test suite
	cd rust-core && cargo test

test-swift: generate-bindings ## Run the Swift/XCTest suite
	xcodebuild test -project $(XCODE_PROJECT) -scheme $(SCHEME)

test: test-rust test-swift ## Run Rust + Swift test suites

clean: ## Remove build outputs, bindings and cargo target
	cd rust-core && cargo clean
	rm -rf $(GENERATED_DIR)
	rm -rf $(BUILD_DIR)
