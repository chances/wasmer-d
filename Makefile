CWD := $(shell pwd)
SOURCES := $(shell find source -name '*.d')
TARGET_OS := $(shell uname -s)
LIBS_PATH := lib

.DEFAULT_GOAL := docs
all: docs

wasmer: $(WASMER_DIR)/lib/libwasmer.a
	@mkdir -p lib
	@cp $(WASMER_DIR)/lib/libwasmer.a lib/.
.PHONY : wasmer

source/wasmer/bindings/package.d:
	dub run dpp -- --preprocess-only --no-sys-headers --ignore-macros --include-path "/usr/lib/llvm-6.0/lib/clang/6.0.0/include" --include-path "$(WASMER_DIR)/include" source/wasmer/bindings/wasmer.dpp
	@mv source/wasmer/bindings/wasmer.d source/wasmer/bindings/package.d

EXAMPLES := bin/hello-world
examples: $(EXAMPLES)
.PHONY: examples

# HELLO_WORLD_SOURCES := $(shell find examples/hello-world/source -name '*.d')
# HELLO_WORLD_JS := $(shell find examples/hello-world/source -name '*.js')
# bin/hello-world: $(SOURCES) $(HELLO_WORLD_SOURCES) $(HELLO_WORLD_JS)
# 	cd examples/hello-world && dub build

# hello-world: bin/hello-world
# 	@bin/hello-world
# .PHONY: hello-world

test:
	env LD_LIBRARY_PATH=$(WASMER_DIR)/lib dub test --parallel
.PHONY: test

cover: $(SOURCES)
	env LD_LIBRARY_PATH=$(WASMER_DIR)/lib dub test --parallel --coverage

PACKAGE_VERSION := 0.1.0
docs/sitemap.xml: $(SOURCES)
	dub build -b ddox
	@echo "Performing cosmetic changes..."
	# Page Titles & Favicon
	@sed -i "s/<\/title>/ - wasmer-d<\/title><link rel=\"shortcut icon\" href=\"https:\/\/github.com\/WebAssembly\/web-assembly-logo\/raw\/bcebf215c6ec0bdd87a3b0d8fddc0bb69d93e26a\/dist\/icon\/web-assembly-icon.svg\">/" `find docs -name '*.html'`
	# Navigation Sidebar
	@sed -i -e "/<nav id=\"main-nav\">/r views/nav.html" -e "/<nav id=\"main-nav\">/d" `find docs -name '*.html'`
	# Index
	@sed -i "s/API documentation/API Reference/g" docs/index.html
	@sed -i -e "/<h1>API Reference<\/h1>/r views/index.html" -e "/<h1>API Reference<\/h1>/d" docs/index.html
	# License Link
	@sed -i "s/<p>MIT License/<p><a href=\"https:\/\/opensource.org\/licenses\/MIT\">MIT License<\/a>/" `find docs -name '*.html'`
	# Footer
	@sed -i -e "/<p class=\"faint\">Generated using the DDOX documentation generator<\/p>/r views/footer.html" -e "/<p class=\"faint\">Generated using the DDOX documentation generator<\/p>/d" `find docs -name '*.html'`
	# Dub Package Version
	@echo `git describe --tags --abbrev=0`
	@sed -i "s/DUB_VERSION/$(PACKAGE_VERSION)/g" `find docs -name '*.html'`
	@echo Done

docs: docs/sitemap.xml
.PHONY: docs

clean: clean-docs
	rm -f source/wasmer/bindings/package.d
	rm -f bin/headless
	rm -f $(EXAMPLES)
	rm -f -- *.lst
.PHONY: clean

clean-docs:
	rm -f docs.json
	rm -f docs/sitemap.xml docs/file_hashes.json
	rm -rf `find docs -name '*.html'`
.PHONY: clean-docs
