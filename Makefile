PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
TEMPLATES := $(HOME)/.config/cal-add/templates.json

.PHONY: build test install install-templates uninstall clean

build:
	swift build -c release

test:
	swift test

install: build
	install -d "$(BINDIR)"
	install -m 755 .build/release/cal-add "$(BINDIR)/cal-add"
	@echo "Installed $(BINDIR)/cal-add"

# Copies the example templates, but never over an existing file.
install-templates:
	@if [ -e "$(TEMPLATES)" ]; then \
		echo "$(TEMPLATES) already exists; leaving it alone"; \
	else \
		install -d "$(dir $(TEMPLATES))" && \
		install -m 644 templates.example.json "$(TEMPLATES)" && \
		echo "Installed $(TEMPLATES)"; \
	fi

uninstall:
	rm -f "$(BINDIR)/cal-add"

clean:
	swift package clean
