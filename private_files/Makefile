CC      ?= gcc
CFLAGS  ?= -O2 -fno-plt -Wall -Wextra
BIN      = switchback
SRC      = src/switchback.c src/dispatch.S src/vm.S src/say.S

all: dist/$(BIN)

build/$(BIN): $(SRC)
	@mkdir -p build
	$(CC) $(CFLAGS) -o $@ $^

dist/$(BIN): build/$(BIN)
	@mkdir -p dist
	cp $< $@
	strip -s $@

clean:
	rm -rf build dist/$(BIN)

.PHONY: all clean
