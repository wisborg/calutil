PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
# The same place calutil looks: $CALUTIL_TEMPLATES, else $XDG_CONFIG_HOME/calutil, else ~/.config/calutil.
CONFIG_HOME := $(or $(XDG_CONFIG_HOME),$(HOME)/.config)
# A leading ~ is expanded, as calutil does, in case the variable was set with it quoted.
TEMPLATES := $(patsubst ~/%,$(HOME)/%,$(or $(CALUTIL_TEMPLATES),$(CONFIG_HOME)/calutil/templates.json))

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
