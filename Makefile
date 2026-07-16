SWIFT := swift
APP := FFMpegasus

.PHONY: build run test clean

build:
	$(SWIFT) build

run:
	$(SWIFT) run $(APP)

test:
	$(SWIFT) test

clean:
	$(SWIFT) package clean
