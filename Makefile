# Team entry points. Run `make` to list them.
SHELL := /bin/bash
PROJECT := SkyAndPlanets
SCHEME  := SkyAndPlanets
DEST    := platform=visionOS Simulator,name=Apple Vision Pro,OS=latest

.DEFAULT_GOAL := help
.PHONY: help bootstrap generate open lint lint-fix build test clean feature spike release hotfix version

help: ## List targets
	grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-11s\033[0m %s\n", $$1, $$2}'

bootstrap: ## One-time machine setup: brew tools, Git LFS, hooks, local config, project
	./scripts/bootstrap.sh

generate: ## Generate $(PROJECT).xcodeproj from project.yml
	@[ -f Configs/Local.xcconfig ] || cp Configs/Local.xcconfig.example Configs/Local.xcconfig
	xcodegen generate

open: generate ## Generate and open the project in Xcode
	open $(PROJECT).xcodeproj

lint: ## SwiftLint, strict (same as CI)
	swiftlint lint --strict

lint-fix: ## Auto-fix what SwiftLint can, then lint
	swiftlint --fix --quiet && swiftlint lint --strict

build: generate ## Build for the visionOS simulator
	set -o pipefail; xcodebuild build -project $(PROJECT).xcodeproj -scheme $(SCHEME) -destination '$(DEST)' CODE_SIGNING_ALLOWED=NO -quiet

test: generate ## Run unit tests on the visionOS simulator
	set -o pipefail; xcodebuild test -project $(PROJECT).xcodeproj -scheme $(SCHEME) -destination '$(DEST)' CODE_SIGNING_ALLOWED=NO -quiet

clean: ## Remove generated project and build output
	rm -rf $(PROJECT).xcodeproj build DerivedData *.xcresult

# ---- GitFlow helpers (see CONTRIBUTING.md) ----
feature: ## Start a feature from develop:  make feature NAME=AR126-12-orbit-gesture
	./scripts/gitflow.sh feature "$(NAME)"

spike: ## Start a throwaway spike from develop:  make spike NAME=AR126-27-shared-space
	./scripts/gitflow.sh spike "$(NAME)"

release: ## Cut a release branch from develop:  make release VERSION=0.2.0
	./scripts/gitflow.sh release "$(VERSION)"

hotfix: ## Start a hotfix from main:  make hotfix VERSION=0.2.1
	./scripts/gitflow.sh hotfix "$(VERSION)"

version: ## Bump MARKETING_VERSION and CHANGELOG:  make version VERSION=0.2.0
	./scripts/gitflow.sh bump "$(VERSION)"
