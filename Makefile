PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin

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

# Copies the example templates, but never over an existing file. Uses the same place
# calutil looks: $CALUTIL_TEMPLATES, else $XDG_CONFIG_HOME/calutil, else ~/.config/calutil.
# Worked out in the shell so the path is used exactly as given; a leading ~ is expanded,
# as calutil does, in case the variable was set with it quoted.
install-templates:
	@t="$${CALUTIL_TEMPLATES:-$${XDG_CONFIG_HOME:-$$HOME/.config}/calutil/templates.json}"; \
	case "$$t" in "~") t="$$HOME" ;; "~/"*) t="$$HOME/$${t#"~/"}" ;; esac; \
	if [ -e "$$t" ]; then \
		echo "$$t already exists; leaving it alone"; \
	else \
		install -d "$$(dirname "$$t")" && \
		install -m 644 templates.example.json "$$t" && \
		echo "Installed $$t"; \
	fi

uninstall:
	rm -f "$(BINDIR)/calutil"

clean:
	swift package clean
