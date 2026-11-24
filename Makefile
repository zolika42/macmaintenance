SHELL := /bin/bash
.DEFAULT_GOAL := help
INSTALL_DIR ?= /Applications
.PHONY: help doctor build dev test lint quality release verify-release verify-install install uninstall install-backups rollback clean backup
help:
	@printf '%s\n' 'MacMaintenance — local workflow' 'make doctor | build | dev | test | lint | quality' 'make release | verify-release | verify-install | install | uninstall | install-backups | rollback | clean | backup' 'Optional: make install INSTALL_DIR="$$HOME/Applications"'
doctor:
	@bash Scripts/doctor.sh
build:
	@bash Scripts/build.sh release
dev:
	@bash Scripts/build.sh debug
	@open build/MacMaintenance.app
test:
	@swift test
lint:
	@for f in Scripts/*.sh; do bash -n "$$f" || exit; done
	@plutil -lint Resources/Info.plist
	@swift package dump-package >/dev/null
	@echo '=== SOURCE_CONFIG_CHECK_PASS ==='
quality: doctor lint test build
	@echo '=== QUALITY_PASS ==='
release: build
	@bash Scripts/release.sh
verify-release:
	@bash Scripts/verify-release.sh
verify-install: build
	@bash Scripts/verify-install.sh
install: build
	@INSTALL_DIR="$(INSTALL_DIR)" bash Scripts/install.sh install
uninstall:
	@INSTALL_DIR="$(INSTALL_DIR)" bash Scripts/install.sh uninstall
install-backups:
	@INSTALL_DIR="$(INSTALL_DIR)" bash Scripts/install.sh backups
rollback:
	@INSTALL_DIR="$(INSTALL_DIR)" bash Scripts/install.sh rollback "$(BACKUP)"
clean:
	@swift package clean
	@echo 'SwiftPM build cache cleaned; install backups retained.'
backup:
	@mkdir -p Releases
	@git bundle create "Releases/MacMaintenance-$$(date +%Y%m%d-%H%M%S).bundle" --all
	@echo 'Local Git backup created (committed history only).'

.PHONY: native-acceptance prepare-public-release
native-acceptance:
	@MM_NATIVE_LAUNCHD_QA=1 swift test --filter NativePublicAcceptanceTests
prepare-public-release:
	@bash Scripts/prepare-public-release.sh
