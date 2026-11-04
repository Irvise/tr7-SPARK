.PHONY: all build test prove bench clean

all: build

build:
	./scripts/build.sh

test: build
	./scripts/test.sh

prove:
	./scripts/prove.sh

bench:
	./scripts/bench.sh

clean:
	rm -rf tr7/obj tr7/lib tr7i/obj tr7i/bin tr7_c/obj tr7_c/lib bench/obj
