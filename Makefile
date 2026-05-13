.PHONY: test lint check install release

test:
	bats tests/*.bats

lint:
	shellcheck install.sh uninstall.sh
	shfmt -d -i 2 -ci install.sh uninstall.sh
	zsh -n gssh.zsh
	zsh -n _gssh

check: lint test

install:
	mkdir -p "$${GSSH_HOME:-$$HOME/.gssh}"
	cp gssh.zsh _gssh "$${GSSH_HOME:-$$HOME/.gssh}/"
	@echo "Installed. Run 'exec zsh' to reload."

release:
ifndef VERSION
	$(error Usage: make release VERSION=1.2.0)
endif
	@if git diff --quiet && git diff --cached --quiet; then true; else \
		echo "Error: working tree is dirty. Commit or stash changes first." >&2; exit 1; \
	fi
	@echo "Releasing v$(VERSION)..."
	sed -i.bak 's/^GSSH_VERSION=".*"/GSSH_VERSION="$(VERSION)"/' gssh.zsh && rm -f gssh.zsh.bak
	git add gssh.zsh
	git commit -m "release: v$(VERSION)"
	git tag -a "v$(VERSION)" -m "v$(VERSION)"
	git push origin master --tags
	@echo ""
	@echo "Released v$(VERSION)"
