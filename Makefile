.PHONY: lint test test-and-lint package

# Tool paths default to common locations; override with env vars or make args.
LUACHECK ?= /Users/rat/.luarocks/bin/luacheck
LUA54 ?= /opt/homebrew/opt/lua@5.4/bin/lua5.4
BUSTED ?= busted

VERSION := $(shell sed -n 's/.*"version": "\([^"]*\)".*/\1/p' info.json)
MOD_NAME := logistic-nexus
PACKAGE_DIR := $(MOD_NAME)_$(VERSION)
RELEASES_DIR := releases
PACKAGE_ZIP := $(RELEASES_DIR)/$(PACKAGE_DIR).zip

lint:
	PATH="/Users/rat/.luarocks/bin:/opt/homebrew/opt/lua@5.4/bin:$${PATH}" $(LUACHECK) .

test:
	$(BUSTED) spec

test-and-lint: test lint

package: test
	@echo "Packaging $(MOD_NAME) $(VERSION)..."
	@rm -rf $(PACKAGE_DIR) $(RELEASES_DIR)
	@mkdir -p $(RELEASES_DIR)
	@mkdir -p $(PACKAGE_DIR)
	@cp -r changelog.txt control.lua data-final-fixes.lua data.lua graphics info.json locale NOTICE.md prototypes scripts settings.lua $(PACKAGE_DIR)/
	@test -f LICENSE.md && cp LICENSE.md $(PACKAGE_DIR)/ || true
	@test -f README.md && cp README.md $(PACKAGE_DIR)/ || true
	@zip -r $(PACKAGE_DIR).zip $(PACKAGE_DIR) >/dev/null
	@mv $(PACKAGE_DIR).zip $(RELEASES_DIR)/
	@rm -rf $(PACKAGE_DIR)
	@echo "Created $(PACKAGE_ZIP)"
