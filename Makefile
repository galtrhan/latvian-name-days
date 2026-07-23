.PHONY: all build install clean run

CC       ?= cc
CFLAGS   ?= -O2 -s -ffunction-sections -fdata-sections
LDFLAGS  ?= -Wl,--gc-sections
OUT_DIR  := dist
BINARY   := $(OUT_DIR)/lnd
SRCS     := lnd.c data.c

all: build

build: $(BINARY)

$(BINARY): $(SRCS) data.h
	@mkdir -p $(OUT_DIR)
	$(CC) $(CFLAGS) $(SRCS) -o $(BINARY) $(LDFLAGS)

install: build
	install -Dm755 $(BINARY) $(HOME)/.local/bin/lnd

run: build
	$(BINARY) $(ARGS)

clean:
	rm -rf $(OUT_DIR)
