.PHONY: help build test e2e setup-axe-driver clean

help:
	@echo "Common AXe commands"
	@echo "  make build   Build AXe"
	@echo "  make test    Run default tests (non-E2E)"
	@echo "  make e2e     Run full E2E flow (build + simulator tests)"
	@echo "  make setup-axe-driver   Build IDB dependencies and axe-driver"
	@echo "  make clean   Clean Swift build artifacts"

build:
	swift build

test:
	swift test

e2e:
	./test-runner.sh

setup-axe-driver:
	./scripts/build.sh setup
	./scripts/build.sh frameworks
	./scripts/build.sh install
	./scripts/build.sh strip
	./scripts/build.sh xcframeworks
	cd Driver && swift build --product axe-driver -c release

clean:
	swift package clean
