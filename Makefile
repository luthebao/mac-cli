.PHONY: build test release install clean fmt help

# VERSION can be overridden on the command line (e.g. `make build VERSION=1.2.3`)
# or via the environment. Default falls back to whatever main.odin declares.
VERSION    ?= $(shell grep '^VERSION ::' src/main.odin | sed -E 's/.*"([^"]+)".*/\1/')
ARCH       := $(shell uname -m | sed 's/x86_64/amd64/')
TARGET     := build/mac-cli
TARBALL    := build/mac-cli-v$(VERSION)-darwin-$(ARCH).tar.gz
ODIN_FLAGS := -collection:mc=src -define:VERSION=$(VERSION)

help:
	@echo "mac-cli build targets:"
	@echo "  make build      Debug build → $(TARGET)"
	@echo "  make release    Optimized build + tar → $(TARBALL)"
	@echo "  make test       Run odin tests"
	@echo "  make fmt        Format src/"
	@echo "  make install    Install to /usr/local/bin (sudo) or ~/.local/bin"
	@echo "  make clean      Remove build/"

build:
	@mkdir -p build
	odin build src -out:$(TARGET) -debug $(ODIN_FLAGS)

release:
	@mkdir -p build
	odin build src -out:$(TARGET) -o:speed $(ODIN_FLAGS)
	strip $(TARGET) || true
	cd build && tar -czf mac-cli-v$(VERSION)-darwin-$(ARCH).tar.gz mac-cli
	@echo "Artifact: $(TARBALL)"
	@shasum -a 256 $(TARBALL)

test:
	odin test src/fsx $(ODIN_FLAGS)
	odin test src/clean/store $(ODIN_FLAGS)
	odin test src/clean/monitor $(ODIN_FLAGS)
	odin test src/clean/cmd $(ODIN_FLAGS)

fmt:
	@command -v odinfmt >/dev/null 2>&1 && odinfmt -w src || echo "odinfmt not installed; skipping"

install: build
	@if [ -w /usr/local/bin ]; then \
		install -m 0755 $(TARGET) /usr/local/bin/mac-cli; \
		echo "Installed /usr/local/bin/mac-cli"; \
	else \
		mkdir -p $$HOME/.local/bin; \
		install -m 0755 $(TARGET) $$HOME/.local/bin/mac-cli; \
		echo "Installed $$HOME/.local/bin/mac-cli (add to PATH if needed)"; \
	fi

clean:
	rm -rf build
