PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
TEMPLATES := $(HOME)/.config/calutil/templates.json

.PHONY: build test install install-templates uninstall clean

build:
	swift build -c release

test:
	swift test

install: build
	install -d "$(BINDIR)"
	install -m 755 .build/release/calutil "$(BINDIR)/calutil"
	@echo "Installed $(BINDIR)/calutil"
	@# This tool used to be called cal-add.
	@if [ -e "$(BINDIR)/cal-add" ]; then rm -f "$(BINDIR)/cal-add" && echo "Removed the old $(BINDIR)/cal-add"; fi

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
	rm -f "$(BINDIR)/calutil"

clean:
	swift package clean
