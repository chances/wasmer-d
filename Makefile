CWD := $(shell pwd)
SOURCES := $(shell find source -name '*.d')
TARGET_OS := $(shell uname -s)
LIBS_PATH := lib

.DEFAULT_GOAL := docs
all: docs

thirdparty/moddable.zip:
	wget https://github.com/Moddable-OpenSource/moddable/archive/OS201116.zip -q --show-progress -O thirdparty/moddable.zip
thirdparty/moddable: thirdparty/moddable.zip
	unzip thirdparty/moddable.zip -d thirdparty
	@mv thirdparty/moddable-OS201116 thirdparty/moddable
wasmer: thirdparty/moddable
	@cd thirdparty/moddable/wasmer/makefiles/lin && env MODDABLE="$(CWD)/thirdparty/moddable" make -f xsc.mk
	@rm -f lib/libwasmer.a
	ar cr lib/libwasmer.a \
		thirdparty/moddable/build/tmp/lin/debug/xsl/xsDefaults.o \
		`find thirdparty/moddable/build/tmp/lin/debug/lib -name '*.o' ! -name 'xsc.c.o' ! -name 'xsmc.c.o'`
.PHONY : wasmer
wasmer-release: thirdparty/moddable
	@cd thirdparty/moddable/wasmer/makefiles/lin && env MODDABLE="$(CWD)/thirdparty/moddable" make GOAL=release -f xsc.mk
	@rm -f lib/libwasmer.a
	ar cr lib/libwasmer.a `find thirdparty/moddable/build/tmp/lin/release/xst -name '*.o' ! -name 'xst.o'`
.PHONY : wasmer-release

source/wasmer/bindings/package.d:
	dub run dpp -- --preprocess-only --no-sys-headers --ignore-macros --include-path "/usr/lib/llvm-6.0/lib/clang/6.0.0/include" --include-path "$(WASMER_DIR)/include" source/wasmer/bindings/wasmer.dpp
	@mv source/wasmer/bindings/wasmer.d source/wasmer/bindings/package.d

EXAMPLES := bin/hello-world
examples: $(EXAMPLES)
.PHONY: examples

HELLO_WORLD_SOURCES := $(shell find examples/hello-world/source -name '*.d')
HELLO_WORLD_JS := $(shell find examples/hello-world/source -name '*.js')
bin/hello-world: $(SOURCES) $(HELLO_WORLD_SOURCES) $(HELLO_WORLD_JS)
	cd examples/hello-world && dub build

hello-world: bin/hello-world
	@bin/hello-world
.PHONY: hello-world

test:
	dub test --parallel
.PHONY: test

cover: $(SOURCES)
	dub test --parallel --coverage

PACKAGE_VERSION := 0.1.0-alpha.1
docs/sitemap.xml: $(SOURCES)
	dub build -b ddox
	@echo "Performing cosmetic changes..."
	# Navigation Sidebar
	@sed -i -e "/<nav id=\"main-nav\">/r views/nav.html" -e "/<nav id=\"main-nav\">/d" `find docs -name '*.html'`
	# Page Titles
	@sed -i "s/<\/title>/ - xs-d<\/title>/" `find docs -name '*.html'`
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

clean:
	rm -f source/wasmer/bindings/package.d
	rm -f bin/headless
	rm -f $(EXAMPLES)
	rm -f docs.json
	rm -f docs/sitemap.xml docs/file_hashes.json
	rm -rf `find docs -name '*.html'`
	rm -f -- *.lst
.PHONY: clean
