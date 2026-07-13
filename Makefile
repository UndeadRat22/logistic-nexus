.PHONY: lint test test-and-lint

LUACHECK = /Users/rat/.luarocks/bin/luacheck
LUA54 = /opt/homebrew/opt/lua@5.4/bin/lua5.4
BUSTED = busted

lint:
	PATH="/Users/rat/.luarocks/bin:/opt/homebrew/opt/lua@5.4/bin:$${PATH}" $(LUACHECK) .

test:
	$(BUSTED) spec

test-and-lint: test lint
