BINARY        := gst-decklink-ndi
BINARY_DEST   := /usr/local/bin/$(BINARY)
CONFIG_DIR    := /etc/$(BINARY)
LOG_DIR       := /var/log/$(BINARY)
PLIST_NAME    := com.$(BINARY).plist
PLIST_DEST    := $(HOME)/Library/LaunchAgents/$(PLIST_NAME)

.PHONY: build release install uninstall load unload logs check clean

## Build debug binary
build:
	swift build

## Build optimised release binary
release:
	swift build -c release

## Install release binary, config, and log dir (requires sudo)
install: release
	sudo install -m 755 .build/release/$(BINARY) $(BINARY_DEST)
	sudo mkdir -p $(CONFIG_DIR)
	@if [ ! -f $(CONFIG_DIR)/config.json ]; then \
	    sudo cp config.json $(CONFIG_DIR)/config.json; \
	    echo "Config installed at $(CONFIG_DIR)/config.json"; \
	else \
	    echo "Config already exists at $(CONFIG_DIR)/config.json (not overwritten)"; \
	fi
	sudo mkdir -p $(LOG_DIR)
	sudo chown $(shell whoami) $(LOG_DIR)
	@echo "Installed $(BINARY_DEST)"

## Remove binary and config (keeps log dir)
uninstall:
	sudo rm -f $(BINARY_DEST)
	@echo "Removed $(BINARY_DEST)"
	@echo "Config at $(CONFIG_DIR) and logs at $(LOG_DIR) are preserved."

## Install plist and load the LaunchAgent
load: install
	@mkdir -p $(HOME)/Library/LaunchAgents
	cp $(PLIST_NAME) $(PLIST_DEST)
	launchctl load $(PLIST_DEST)
	@echo "LaunchAgent loaded. Check status with: launchctl list | grep $(BINARY)"

## Unload the LaunchAgent
unload:
	-launchctl unload $(PLIST_DEST) 2>/dev/null || true
	@echo "LaunchAgent unloaded."

## Tail the service logs
logs:
	tail -F $(LOG_DIR)/stdout.log $(LOG_DIR)/stderr.log

## Run dependency check (dry-run mode)
check:
	@if [ -x $(BINARY_DEST) ]; then \
	    $(BINARY_DEST) --dry-run; \
	else \
	    swift run $(BINARY) --dry-run; \
	fi

## Remove build artefacts
clean:
	swift package clean
	rm -rf .build
