SHELL := /bin/bash

# Prefer system flutter when available, otherwise use FVM.
FLUTTER_BIN := $(shell command -v flutter 2>/dev/null)
ifeq ($(FLUTTER_BIN),)
FLUTTER := fvm flutter
else
FLUTTER := flutter
endif

PYTHON ?= python3
PIP ?= pip3

.PHONY: help doctor deps deps-python deps-flutter clean format analyze test check \
	build-sidecar build-macos build-all run run-macos

help:
	@echo "PadVibe Make targets"
	@echo ""
	@echo "  make deps            - Install Flutter and Python dependencies"
	@echo "  make deps-flutter    - flutter pub get"
	@echo "  make deps-python     - pip install -r sidecar/requirements.txt"
	@echo "  make doctor          - Show Flutter and Python versions"
	@echo "  make format          - Format Dart files"
	@echo "  make analyze         - Run flutter analyze"
	@echo "  make test            - Run flutter tests"
	@echo "  make check           - analyze + test"
	@echo "  make clean           - flutter clean"
	@echo "  make build-sidecar   - Build/sign Python sidecar binary"
	@echo "  make build-macos     - Build macOS release app"
	@echo "  make build-all       - Build sidecar + macOS release"
	@echo "  make run             - Run Flutter app (default target platform)"
	@echo "  make run-macos       - Run Flutter app on macOS desktop"

doctor:
	@echo "Flutter:"
	@$(FLUTTER) --version
	@echo ""
	@echo "Python:"
	@$(PYTHON) --version
	@echo ""
	@echo "Pip:"
	@$(PIP) --version

deps: deps-flutter deps-python

deps-flutter:
	$(FLUTTER) pub get

deps-python:
	$(PIP) install -r sidecar/requirements.txt

clean:
	$(FLUTTER) clean

format:
	dart format lib test

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test

check: analyze test

build-sidecar:
	./sidecar/build_sidecar.sh

build-macos:
	$(FLUTTER) build macos --release

build-all: build-sidecar build-macos

run:
	$(FLUTTER) run

run-macos:
	$(FLUTTER) run -d macos
