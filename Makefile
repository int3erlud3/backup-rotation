SHELL_FILES := bin/backup-rotation tests/backup-rotation.bats
GITLEAKS_IMAGE := ghcr.io/gitleaks/gitleaks:v8.30.1

.PHONY: all lint test scan
all: lint test

lint:
	shellcheck -x -S style $(SHELL_FILES)

test:
	bats tests

scan:
	docker run --rm -v "$(CURDIR):/repo:ro" $(GITLEAKS_IMAGE) dir /repo --redact --no-banner
