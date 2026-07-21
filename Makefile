SWIFT := swift
APP := FFMpegasus

.PHONY: build run test clean fixtures fixtures-validate fixtures-clean

build:
	$(SWIFT) build

run:
	$(SWIFT) run $(APP)

test:
	$(SWIFT) test

clean:
	$(SWIFT) package clean

fixtures:
	scripts/fixtures.sh generate

fixtures-validate:
	scripts/fixtures.sh validate

fixtures-clean:
	scripts/fixtures.sh clean
