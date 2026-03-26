.PHONY: test install

test:
	bats tests/*.bats

install:
	cp gssh.zsh _gssh "$${GSSH_HOME:-$$HOME/.gssh}/"
	@echo "Installed. Run 'exec zsh' to reload."
