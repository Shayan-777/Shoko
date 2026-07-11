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

.PHONY: native clean
