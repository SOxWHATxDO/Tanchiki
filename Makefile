# =============================================================================
#  TANKS - SNES prototype built with pvsneslib
# -----------------------------------------------------------------------------
#  make            build the ROM (tanks.sfc)
#  make run        build and launch it in an emulator
#  make verbose    build without the log wrapper (full compiler output)
#  make clean      delete every generated file
#  make help       show the project layout and all targets
#
#  Requires PVSNESLIB_HOME, see
#  https://github.com/alekmaul/pvsneslib/wiki/Installation
# =============================================================================

ifeq ($(strip $(PVSNESLIB_HOME)),)
$(error "PVSNESLIB_HOME is not set: see https://github.com/alekmaul/pvsneslib/wiki/Installation")
endif

# -----------------------------------------------------------------------------
# 1. Cartridge identity
# -----------------------------------------------------------------------------
ROMNAME  ?= tanks
ROMTITLE ?= TANKS PROTOTYPE
export ROMNAME
export ROMTITLE

# ROMBANKS is the number of 32 KiB (LoROM) or 64 KiB (HiROM) banks in the image.
# The cartridge header stores the ROM size as log2(size in KiB), so derive it
# from ROMBANKS instead of letting it go stale when the project grows.
ROMBANKS  ?= 8
HIROM     ?= 0
FASTROM   ?= 0

ROM_BANK_KB  := $(if $(filter 1,$(HIROM)),64,32)
ROM_TOTAL_KB := $(shell echo $$(( $(ROMBANKS) * $(ROM_BANK_KB) )))
ROMSIZE      ?= $(shell n=$(ROM_TOTAL_KB); e=0; \
                       while [ "$$n" -gt 1 ]; do n=$$((n/2)); e=$$((e+1)); done; echo $$e)

# snes_rules rewrites HIROM/FASTROM to filtered values, so keep a readable copy
# for the help target.
CART_BANKS := $(ROMBANKS)
CART_KB    := $(ROM_TOTAL_KB)
CART_KIND  := $(if $(filter 1,$(HIROM)),HiROM,LoROM)/$(if $(filter 1,$(FASTROM)),FastROM,SlowROM)

# -----------------------------------------------------------------------------
# 2. Project layout
#    src/       hand-written code (C and asm), scanned by pvsneslib rules
#    res/gfx/   source art (indexed PNG), converted into build/gfx
#    res/audio/ source modules (.it), converted into build/soundbank.*
#    build/     everything generated (safe to delete)
# -----------------------------------------------------------------------------
SRC   ?= src
BUILD ?= build

GFX_OUT   := $(BUILD)/gfx
SOUNDBANK := $(BUILD)/soundbank

export SRC
export SOUNDBANK

# -----------------------------------------------------------------------------
# 3. Audio
#    Effects MUST be listed before music and are converted with -f so that
#    snesmod can stream them. Keep the whole soundbank under ~57 KiB.
# -----------------------------------------------------------------------------
SFX_IT     := $(sort $(wildcard res/audio/sfx/*.it))
MUSIC_IT   := $(sort $(wildcard res/audio/music/*.it))
AUDIOFILES := $(strip $(SFX_IT) $(MUSIC_IT))

SMCONVFLAGS := -s -o $(SOUNDBANK) -V -b 5 $(if $(strip $(SFX_IT)),-f)

# -----------------------------------------------------------------------------
# 4. Graphics
#    One PNG per asset. gfx4snes reads pixel indices directly, so the source
#    must be an indexed (palette) PNG whose first N entries are the SNES
#    colours (16 for backgrounds/sprites, 2 for the font).
#
#      backgrounds/ -> tiles + tilemap + palette (-m)
#      sprites/     -> 16x16 sprite tiles + palette
#      fonts/       -> 8x8 font tiles + tilemap, no tile reduction (-R)
# -----------------------------------------------------------------------------
GFX_BG_SRC   := $(sort $(wildcard res/gfx/backgrounds/*.png))
GFX_SPR_SRC  := $(sort $(wildcard res/gfx/sprites/*.png))
GFX_FONT_SRC := $(sort $(wildcard res/gfx/fonts/*.png))

GFX_BG_FLAGS   ?= -s 8  -o 16 -u 16 -e 0 -p -m
GFX_SPR_FLAGS  ?= -s 16 -o 16 -u 16 -p
GFX_FONT_FLAGS ?= -s 8  -o 2  -u 16 -e 1 -p -m -R

GFX_BG_STAMPS   := $(patsubst res/gfx/backgrounds/%.png,$(GFX_OUT)/backgrounds/%.stamp,$(GFX_BG_SRC))
GFX_SPR_STAMPS  := $(patsubst res/gfx/sprites/%.png,$(GFX_OUT)/sprites/%.stamp,$(GFX_SPR_SRC))
GFX_FONT_STAMPS := $(patsubst res/gfx/fonts/%.png,$(GFX_OUT)/fonts/%.stamp,$(GFX_FONT_SRC))
GFX_STAMPS      := $(GFX_BG_STAMPS) $(GFX_SPR_STAMPS) $(GFX_FONT_STAMPS)

# -----------------------------------------------------------------------------
# 5. pvsneslib build rules (compiler, linker, ROM, clean* targets)
# -----------------------------------------------------------------------------
include $(PVSNESLIB_HOME)/devkitsnes/snes_rules

# Generated headers (soundbank.h, *.inc) live in build/, so C code can simply
# do #include "soundbank.h".
CFLAGS += -I$(CURDIR)/$(BUILD)

# -----------------------------------------------------------------------------
# 6. Generated directories
# -----------------------------------------------------------------------------
$(BUILD) $(GFX_OUT)/backgrounds $(GFX_OUT)/sprites $(GFX_OUT)/fonts:
	@mkdir -p $@

# -----------------------------------------------------------------------------
# 7. Art conversion
#    gfx4snes always writes next to its input, so the rule moves the results
#    into build/gfx/<kind>/ and leaves res/ as a pure source tree.
# -----------------------------------------------------------------------------
$(GFX_OUT)/backgrounds/%.stamp: res/gfx/backgrounds/%.png | $(GFX_OUT)/backgrounds
	@echo "  gfx    backgrounds/$*.png -> tiles, map, palette"
	@$(GFXCONV) $(GFX_BG_FLAGS) -t png -i $<
	@set -e; for ext in pic map pal inc; do \
		if [ -f "res/gfx/backgrounds/$*.$$ext" ]; then \
			mv -f "res/gfx/backgrounds/$*.$$ext" "$(GFX_OUT)/backgrounds/"; \
		fi; \
	done
	@rm -f "res/gfx/backgrounds/$*_data.as"
	@touch $@

$(GFX_OUT)/sprites/%.stamp: res/gfx/sprites/%.png | $(GFX_OUT)/sprites
	@echo "  gfx    sprites/$*.png -> sprite tiles, palette"
	@$(GFXCONV) $(GFX_SPR_FLAGS) -t png -i $<
	@set -e; for ext in pic pal inc; do \
		if [ -f "res/gfx/sprites/$*.$$ext" ]; then \
			mv -f "res/gfx/sprites/$*.$$ext" "$(GFX_OUT)/sprites/"; \
		fi; \
	done
	@rm -f "res/gfx/sprites/$*_data.as"
	@touch $@

$(GFX_OUT)/fonts/%.stamp: res/gfx/fonts/%.png | $(GFX_OUT)/fonts
	@echo "  gfx    fonts/$*.png -> font tiles, map, palette"
	@$(GFXCONV) $(GFX_FONT_FLAGS) -t png -i $<
	@set -e; for ext in pic map pal inc; do \
		if [ -f "res/gfx/fonts/$*.$$ext" ]; then \
			mv -f "res/gfx/fonts/$*.$$ext" "$(GFX_OUT)/fonts/"; \
		fi; \
	done
	@rm -f "res/gfx/fonts/$*_data.as"
	@touch $@

# The soundbank lives in its own directory: make sure it exists before smconv.
ifneq ($(strip $(AUDIOFILES)),)
$(SOUNDBANK).asm: | $(BUILD)
endif

# -----------------------------------------------------------------------------
# 8. Keep the build consistent: recompile code when art or the soundbank change
# -----------------------------------------------------------------------------
OBJS_PREREQS := $(GFX_STAMPS) $(if $(strip $(AUDIOFILES)),$(SOUNDBANK).asm)

ifneq ($(strip $(OFILES)),)
$(OFILES): $(OBJS_PREREQS)
endif

# -----------------------------------------------------------------------------
# 9. Targets
# -----------------------------------------------------------------------------
.PHONY: all buildActual preflight verbose gfx audio clean cleanLogs run help

# `all` goes through the log wrapper from snes_rules: it collects warnings and
# errors and fails the build with a readable summary instead of a wall of text.
all: preflight buildWithSummary

# The wrapper calls this target in a sub-make; graphics and the soundbank are
# pulled in through the OFILES prerequisites above.
buildActual: $(OFILES) $(ROMNAME).sfc

# Same build without the log wrapper, useful when chasing a compiler error.
verbose: preflight
	@$(MAKE) --no-print-directory buildActual

# Convert only (handy while iterating on art).
gfx: $(GFX_STAMPS)

# Convert only the soundbank.
audio: $(if $(strip $(AUDIOFILES)),$(SOUNDBANK).asm)

preflight:
	@test -n "$(strip $(PVSNESLIB_HOME))" || { \
		echo "error: PVSNESLIB_HOME is not set"; exit 1; }
	@test -x "$(GFXCONV)" || { echo "error: gfx4snes not found at $(GFXCONV)"; exit 1; }
	@test -x "$(SMCONV)"  || { echo "error: smconv not found at $(SMCONV)"; exit 1; }
	@test -x "$(CC)"      || { echo "error: 816-tcc not found at $(CC)"; exit 1; }
	@if [ -z "$(strip $(CFILES))" ]; then \
		echo "error: no C sources found under $(SRC)/"; \
		echo "       pvsneslib scans $(SRC)/, $(SRC)/*/ and $(SRC)/*/*/ (three levels)."; \
		echo "       Start with $(SRC)/main.c - see README.md."; \
		exit 1; \
	fi

clean: cleanBuildRes cleanRom cleanGfx cleanAudio cleanLogs
	@echo "  clean  $(BUILD)/"
	@rm -rf $(BUILD)
	@rm -f res/gfx/backgrounds/*_data.as res/gfx/sprites/*_data.as res/gfx/fonts/*_data.as

# -----------------------------------------------------------------------------
# 10. Emulator
# -----------------------------------------------------------------------------
EMULATOR ?= $(firstword $(foreach e,mednafen snes9x-gtk snes9x bsnes-plus bsnes mesen mesen-s retroarch,$(shell command -v $(e) 2>/dev/null)))

run: all
	@if [ -z "$(strip $(EMULATOR))" ]; then \
		echo "error: no emulator found in PATH"; \
		echo "       use: make run EMULATOR=/path/to/emulator"; \
		exit 1; \
	fi
	@echo "  run    $(EMULATOR) $(ROMNAME).sfc"
	@$(EMULATOR) "$(ROMNAME).sfc"

# -----------------------------------------------------------------------------
# 11. Help
# -----------------------------------------------------------------------------
help:
	@echo "TANKS - SNES prototype (pvsneslib)"
	@echo ""
	@echo "  src/                        hand-written code"
	@echo "    main.c                    entry point (create it first)"
	@echo "    game/                     gameplay: tanks, bullets, level, match state"
	@echo "    engine/                   input, OAM sprites, audio, HUD helpers"
	@echo "    data/assets.asm           .incbin manifest, one label per asset"
	@echo "  res/gfx/backgrounds/*.png   tiles + map + palette"
	@echo "  res/gfx/sprites/*.png       16x16 sprite sheets"
	@echo "  res/gfx/fonts/*.png         optional custom font"
	@echo "  res/audio/sfx/*.it          effects (converted first)"
	@echo "  res/audio/music/*.it        music modules"
	@echo "  build/                      generated: gfx, soundbank, objects"
	@echo ""
	@echo "  make            build tanks.sfc"
	@echo "  make run        build and play"
	@echo "  make verbose    build with full compiler output"
	@echo "  make gfx        convert art only"
	@echo "  make audio      convert the soundbank only"
	@echo "  make clean      remove generated files"
	@echo ""
	@echo "  Config: ROMBANKS=$(CART_BANKS) ($(CART_KB) KiB), $(CART_KIND)"
	@echo "  Debug:  PVSNESLIB_DEBUG=1 make"
