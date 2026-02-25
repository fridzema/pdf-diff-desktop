.PHONY: build-rust generate-bindings build-app test-rust test-swift test clean

RUST_TARGET = aarch64-apple-darwin
RUST_LIB = rust-core/target/$(RUST_TARGET)/release/libpdf_diff_core.a
GENERATED_DIR = generated

build-rust:
	cd rust-core && cargo build --release --target $(RUST_TARGET)

generate-bindings: build-rust
	cd rust-core && cargo run --bin uniffi-bindgen generate \
		--library target/$(RUST_TARGET)/release/libpdf_diff_core.dylib \
		-l swift \
		-o ../$(GENERATED_DIR)/

build-app: generate-bindings
	@echo "Run: xcodebuild -project PdfDiffApp/PdfDiffApp.xcodeproj -scheme PdfDiff build"

test-rust:
	cd rust-core && cargo test

test-swift:
	xcodebuild test -project PdfDiffApp/PdfDiffApp.xcodeproj -scheme PdfDiff

test: test-rust test-swift

clean:
	cd rust-core && cargo clean
	rm -rf $(GENERATED_DIR)
