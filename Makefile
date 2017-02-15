# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Default rule.
BUILD ?= obj
all: $(BUILD)/anc

# If ARCH is unset, try to determine the architecture. 
ARCH ?= $(shell uname -m | \
	sed 's/\(aarch64\)/arm64/gi' | \
	sed 's/\(armv7l\)/arm/gi' | \
	sed 's/\(i[3-6]86\)/x86/gi' | \
	sed 's/\(x86_64\)/x86-64/gi')

# Check ARCH against a whitelist.
ARCH := $(filter arm arm64 x86 x86-64 amd64,$(ARCH))

# If ARCH is still unset, then the architecture is not (yet) supported.
ifeq ($(ARCH),)
$(error No support available for the target architecture)
endif

ifeq ($(ARCH),amd64)
ARCH=x86-64
endif

# Include the config file.
CONFIG ?= scripts/config
include $(CONFIG)

# Basic settings.
CFLAGS += -D_GNU_SOURCE -g3 -Wall -Wextra -std=gnu11 -Os -fPIC -fPIE -pie
CFLAGS += -Iinclude
LDFLAGS += -flto -Os -pie
LIBS += -lpthread

ifdef USE_SANITIZERS
CFLAGS += -fsanitize=cfi -fsanitize=safe-stack -flto -fvisibility=hidden
LDFLAGS += -fsanitize=cfi -fsanitize=safe-stack -fvisibility=hidden
endif

obj-y += source/args.o
obj-y += source/buffer.o
obj-y += source/cache.o
obj-y += source/macros.o
obj-y += source/paging.o
obj-y += source/profile.o
obj-y += source/shuffle.o
obj-y += source/solver.o
obj-y += source/sysfs.o
obj-y += source/thread.o
obj-y += source/path.o

anc-obj-y += source/anc.o

revanc-obj-y += source/revanc.o

-include source/$(ARCH)/Makefile

config-header = $(BUILD)/include/config.h
CFLAGS += -I$(BUILD)/include

# Add the build prefix.
obj = $(addprefix $(BUILD)/, $(obj-y))
anc-obj = $(addprefix $(BUILD)/, $(anc-obj-y))
revanc-obj = $(addprefix $(BUILD)/, $(revanc-obj-y))

# Include the dependencies.
dep = $(obj:.o=.d)
-include $(dep)

# Phony targets.
.PHONY: force run clean all

.PRECIOUS: $(BUILD)/var/%

all: $(BUILD)/anc $(BUILD)/revanc

# Rule to link the program.
$(BUILD)/anc: $(obj) $(anc-obj) $(BUILD)/var/LDFLAGS $(BUILD)/var/LIBS
	@echo "LD $@"
	@mkdir -p $(dir $@)
	$(CC) $(obj) $(anc-obj) -o $@ $(LDFLAGS) $(LIBS)

$(BUILD)/revanc: $(obj) $(revanc-obj) $(BUILD)/var/LDFLAGS $(BUILD)/var/LIBS
	@echo "LD $@"
	@mkdir -p $(dir $@)
	$(CC) $(obj) $(revanc-obj) -o $@ $(LDFLAGS) $(LIBS)

# Rule used to detect changed variables.
$(BUILD)/var/%: force
	@mkdir -p $(dir $@)
	@echo $($*) | cmp -s - $@ || echo $($*) > $@

# Rule to compile C source code.
$(BUILD)/%.o: %.c $(BUILD)/var/CFLAGS $(config-header)
	@echo "CC $<"
	@mkdir -p $(dir $@)
	$(CC) -c $< -o $@ $(CFLAGS) -MT $@ -MMD -MP -MF $(@:.o=.d)

# Rule to compile Assembly source code.
$(BUILD)/%.o: %.S $(BUILD)/var/CFLAGS $(config-header)
	@echo "AS $<"
	@mkdir -p $(dir $@)
	$(CC) -c $< -o $@ $(CFLAGS) -MT $@ -MMD -MP -MF $(@:.o=.d)

# Rule to generate a header containing the definitions from the config file.
$(BUILD)/include/config.h: $(CONFIG)
	@echo "GEN $@"
	@mkdir -p $(dir $@)
	@grep -Pi "^CONFIG_[A-Z_]*=.*$$" $(CONFIG) | \
		sed 's/^\(.*\)=\(y\|yes\|1\)$$/#define \1 1/gi' | \
		sed 's/^\(.*\)=\(n\|no\|0\)$$/#undef \1 /gi' | \
		sed 's/^\(.*\)=\(.*\)$$/#define \1 \2/gi' \
		>> $@

# Rule to clean up output files.
clean:
	@rm -rf $(BUILD)

