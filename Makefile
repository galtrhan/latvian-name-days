.PHONY: all build install clean run mirror

ODIN      ?= odin
OUT_DIR   := dist
BINARY    := $(OUT_DIR)/lnd
ODIN_FLAGS := -o:size -disable-assert -extra-linker-flags:-s\ -Wl,--gc-sections

all: build

build: $(BINARY)

$(BINARY): lnd.odin data.odin
	@mkdir -p $(OUT_DIR)
	$(ODIN) build . -out:$(BINARY) $(ODIN_FLAGS)

install: build
	install -Dm755 $(BINARY) $(HOME)/.local/bin/lnd

run: build
	$(BINARY) $(ARGS)

clean:
	rm -rf $(OUT_DIR)

# Push branches to GitHub mirror (Codeberg remains primary via origin).
mirror:
	git push github main
	git push github odin

