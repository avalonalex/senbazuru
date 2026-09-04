# Convenience wrappers. Everything here is a one-line stack/ormolu/hlint call;
# the Makefile exists so that `make check` names the exact set of gates that
# should pass before a commit.

HS_FILES := $(shell find src app test -name '*.hs')

.PHONY: build repl install test fmt fmt-check lint check examples clean

build:
	stack build

# REPL with the library loaded. Picks up ./.ghci, which quiets the
# compiled-code warning set that is unhelpful at a prompt.
repl:
	stack ghci senbazuru:lib

# Put the senbazuru executable on your PATH (~/.local/bin by default), so it
# can be run without the `stack run --` dance.
install:
	stack install

test:
	stack test

# Rewrite sources in place. Formatting is not up for debate; run this.
fmt:
	ormolu --mode inplace $(HS_FILES)

fmt-check:
	ormolu --mode check $(HS_FILES)

lint:
	hlint src app test

# What CI should run.
check: fmt-check lint test

# Re-render every example into build/, for eyeballing changes to the renderer.
examples: build
	mkdir -p build
	@for f in examples/*.fold; do \
		name=$$(basename $$f .fold); \
		stack exec -- senbazuru render $$f -o build/$$name.svg && echo "build/$$name.svg"; \
	done

clean:
	stack clean
	rm -rf build
