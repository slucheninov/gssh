.PHONY: test lint check install

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
