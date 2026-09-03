# Convenience wrappers. Everything here is a one-line stack/ormolu/hlint call;
# the Makefile exists so that `make check` names the exact set of gates that
# should pass before a commit.

HS_FILES := $(shell find src app test -name '*.hs')

.PHONY: build test fmt fmt-check lint check examples clean

build:
	stack build

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
