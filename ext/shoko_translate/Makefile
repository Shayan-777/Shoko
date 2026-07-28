CC      ?= cc
CFLAGS  ?= -O3 -std=c11 -Wall -Wextra
LDLIBS   = -lm

SRC := src/engine.c src/marian_bin.c src/nn.c src/spm.c
HDR := src/marian_bin.h src/nn.h src/spm.h

shoko-translate: $(SRC) $(HDR)
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDLIBS)

# Optimized build for the local machine (not portable across CPUs).
native: CFLAGS += -march=native
native: shoko-translate

clean:
	rm -f shoko-translate

test: shoko-translate
	test/protocol.sh ./shoko-translate
	@binary=$$(mktemp); \
	trap 'rm -f "$$binary"' EXIT HUP INT TERM; \
	$(CC) $(CFLAGS) -Isrc -o "$$binary" test/spm_test.c src/spm.c $(LDLIBS); \
	"$$binary"
	@binary=$$(mktemp); \
	trap 'rm -f "$$binary"' EXIT HUP INT TERM; \
	$(CC) $(CFLAGS) -Isrc -o "$$binary" test/marian_bin_test.c src/marian_bin.c $(LDLIBS); \
	"$$binary"

.PHONY: native clean test
