
.PHONY: lint test install

lint:
	@echo "Linting script..."
	shellcheck aws-mfa.sh

test: lint
	@echo "Running tests..."

install:
	@echo "Installing..."
	cp aws-mfa.sh $$HOME/bin/aws-mfa
