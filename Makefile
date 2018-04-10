.PHONY: all build release

all: build

build:
	coffee -c -o lib src

release: build
	npm publish
