test:
	lua tests/globals.lua
	lua tests/run.lua
	lua tests/smoke.lua
	lua tests/voice.lua
	lua tests/mem.lua
	lua tests/fuzz.lua

# make release V=1.0.0 -> dist/tricky-sticks-fpv-1.0.0.zip holding just SCRIPTS/
# (what goes on the SD card), plus the license.
release: test
	@test -n "$(V)" || (echo "usage: make release V=1.0.0"; exit 1)
	mkdir -p dist
	rm -f dist/tricky-sticks-fpv-$(V).zip
	git archive --format=zip -o dist/tricky-sticks-fpv-$(V).zip HEAD SCRIPTS LICENSE

.PHONY: test release
