#
# Makefile
#
# Copyright (C) 2014 Creytiv.com
#

# Paths to your Android SDK/NDK
NDK_PATH  := $(HOME)/Android/Sdk/ndk-bundle
SDK_PATH  := $(HOME)/Android/Sdk/


PLATFORM  := android-17

# Path to install binaries on your Android-device
TARGET_PATH=/data/local/tmp

# Config path where .baresip directory is located
CONFIG_PATH=/data/local/tmp


OS        := $(shell uname -s | tr "[A-Z]" "[a-z]")

ifeq ($(OS),linux)
	HOST_OS   := linux-x86_64
endif
ifeq ($(OS),darwin)
	HOST_OS   := darwin-x86_64
endif


# Tools
SYSROOT   := $(NDK_PATH)/platforms/$(PLATFORM)/arch-arm
PREBUILT  := $(NDK_PATH)/toolchains/arm-linux-androideabi-4.9/prebuilt
BIN       := $(PREBUILT)/$(HOST_OS)/bin
CC        := $(BIN)/arm-linux-androideabi-gcc
CXX       := $(BIN)/arm-linux-androideabi-g++
RANLIB    := $(BIN)/arm-linux-androideabi-ranlib
AR        := $(BIN)/arm-linux-androideabi-ar
ADB       := $(SDK_PATH)/platform-tools/adb
PWD       := $(shell pwd)

# Compiler and Linker Flags
#
# NOTE: use -isystem to avoid warnings in system header files
CFLAGS    := \
	-isystem $(SYSROOT)/usr/include/ \
	-I$(PWD)/openssl/include \
	-I$(PWD)/opus/include_opus \
	-I$(PWD)/speex/include \
	-I$(PWD)/libzrtp/include \
	-I$(PWD)/libzrtp/third_party/bnlib \
	-I$(PWD)/libzrtp/third_party/bgaes \
	-march=armv7-a \
	-fPIC \
	-DCONFIG_PATH='\"$(CONFIG_PATH)\"'
LFLAGS    := -L$(SYSROOT)/usr/lib/ \
	-L$(PWD)/openssl \
	-L$(PWD)/opus/.libs \
	-L$(PWD)/speex/libspeex/.libs \
	-L$(PWD)/libzrtp \
	-L$(PWD)/libzrtp/third_party/bnlib \
	-fPIE -pie
LFLAGS    += --sysroot=$(NDK_PATH)/platforms/$(PLATFORM)/arch-arm


COMMON_FLAGS := CC=$(CC) \
		CXX=$(CXX) \
		RANLIB=$(RANLIB) \
		AR=$(AR) \
		EXTRA_CFLAGS="$(CFLAGS) -DANDROID" \
		EXTRA_CXXFLAGS="$(CFLAGS) -DANDROID" \
		EXTRA_LFLAGS="$(LFLAGS)" \
		SYSROOT=$(SYSROOT)/usr \
		SYSROOT_ALT= \
		HAVE_LIBRESOLV= \
		HAVE_RESOLV= \
		HAVE_PTHREAD=1 \
		HAVE_PTHREAD_RWLOCK=1 \
		HAVE_LIBPTHREAD= \
		HAVE_INET_PTON=1 \
		HAVE_INET6=1 \
		PEDANTIC= \
		OS=linux ARCH=arm \
		USE_OPENSSL=yes \
		USE_OPENSSL_DTLS=yes \
		USE_OPENSSL_SRTP=yes \
		ANDROID=yes

EXTRA_MODULES := g711 stdio opensles echo appandroid

ifneq ("$(wildcard $(PWD)/opus)","")
	EXTRA_MODULES := $(EXTRA_MODULES) opus
endif

ifneq ("$(wildcard $(PWD)/speex)","")
	EXTRA_MODULES := $(EXTRA_MODULES) speex
endif

ifneq ("$(wildcard $(PWD)/libzrtp)","")
	EXTRA_MODULES := $(EXTRA_MODULES) zrtp
endif

default:	baresip

libre.a: Makefile
	@rm -f re/libre.*
	@make $@ -C re $(COMMON_FLAGS)

librem.a:	Makefile libre.a
	@rm -f rem/librem.*
	@make $@ -C rem $(COMMON_FLAGS)

libbaresip.a:	Makefile librem.a libre.a
	@rm -f baresip/baresip baresip/src/static.c
	PKG_CONFIG_LIBDIR="$(SYSROOT)/usr/lib/pkgconfig" \
	make $@ -C baresip $(COMMON_FLAGS) STATIC=1 \
		LIBRE_SO=$(PWD)/re LIBREM_PATH=$(PWD)/rem \
	        MOD_AUTODETECT= \
		EXTRA_MODULES="$(EXTRA_MODULES)"

.PHONY: baresip
baresip:	Makefile librem.a libre.a
	@rm -f baresip/baresip baresip/src/static.c
	PKG_CONFIG_LIBDIR="$(SYSROOT)/usr/lib/pkgconfig" \
	make $@ -C baresip $(COMMON_FLAGS) STATIC=1 \
		LIBRE_SO=$(PWD)/re LIBREM_PATH=$(PWD)/rem \
	        MOD_AUTODETECT= \
		EXTRA_MODULES="$(EXTRA_MODULES)"

.PHONY: selftest
selftest:	Makefile librem.a libre.a
	@rm -f baresip/selftest baresip/src/static.c
	PKG_CONFIG_LIBDIR="$(SYSROOT)/usr/lib/pkgconfig" \
	make selftest -C baresip $(COMMON_FLAGS) STATIC=1 \
		LIBRE_SO=$(PWD)/re LIBREM_PATH=$(PWD)/rem \
	        MOD_AUTODETECT=
	$(ADB) push baresip/selftest $(TARGET_PATH)/selftest
	$(ADB) shell "cd $(TARGET_PATH) && ./selftest "


install:	baresip
	$(ADB) push baresip/baresip $(TARGET_PATH)/baresip

config:
	$(ADB) push .baresip $(TARGET_PATH)/
	$(ADB) push baresip/share $(TARGET_PATH)/share

clean:
	make distclean -C baresip
	make distclean -C retest
	make distclean -C rem
	make distclean -C re

distclean: clean
	make distclean -C opus
	make distclean -C openssl
	rm -r distribution


.PHONY: openssl
openssl:
	cd openssl && \
		CC=$(CC) RANLIB=$(RANLIB) AR=$(AR) \
		./Configure android no-shared && \
		ANDROID_DEV=$(SYSROOT)/usr \
		CROSS_SYSROOT="$(SYSROOT)" \
		make build_libs

.PHONY: opus
opus:
	cd opus && \
		rm -rf include_opus && \
		CC="$(CC) --sysroot $(SYSROOT)" \
		RANLIB=$(RANLIB) AR=$(AR) PATH=$(BIN):$(PATH) \
		./configure --host=arm-linux-androideabi --disable-shared CFLAGS="-march=armv7-a" && \
		CC="$(CC) --sysroot $(SYSROOT)" \
		RANLIB=$(RANLIB) AR=$(AR) PATH=$(BIN):$(PATH) \
		make && \
		mkdir include_opus && \
		mkdir include_opus/opus && \
		cp include/* include_opus/opus

.PHONY: speex
speex:
	cd speex && \
		CC="$(CC) --sysroot $(SYSROOT)" \
		RANLIB=$(RANLIB) AR=$(AR) PATH=$(BIN):$(PATH) \
		./configure --host=arm-linux-androideabi --disable-shared CFLAGS="-march=armv7-a" && \
		CC="$(CC) --sysroot $(SYSROOT)" \
		RANLIB=$(RANLIB) AR=$(AR) PATH=$(BIN):$(PATH) \
		make

.PHONY: zrtp
zrtp:
	cd libzrtp && \
		./bootstrap.sh && \
		CC="$(CC) --sysroot $(SYSROOT)" \
		RANLIB=$(RANLIB) AR=$(AR) PATH=$(BIN):$(PATH) \
		./configure --host=arm-linux-androideabi CFLAGS="-march=armv7-a" && \
		cd third_party/bnlib/ && \
		CC="$(CC) --sysroot $(SYSROOT)" \
		RANLIB=$(RANLIB) AR=$(AR) PATH=$(BIN):$(PATH) \
		./configure --host=arm-linux-androideabi CFLAGS="-march=armv7-a" && \
		cd ../.. && \
		CC="$(CC) --sysroot $(SYSROOT)" \
		RANLIB=$(RANLIB) AR=$(AR) PATH=$(BIN):$(PATH) \
		make

emulator:
	@$(SDK_PATH)/tools/emulator -avd test

shell:
	@$(ADB) shell

info:
	make $@ -C re $(COMMON_FLAGS)

dump:
	@echo "NDK_PATH = $(NDK_PATH)"
	@echo "SDK_PATH = $(SDK_PATH)"
	@echo "HOST_OS  = $(HOST_OS)"

distri: openssl opus libbaresip.a
	mkdir -p distribution/baresip
	mkdir -p distribution/baresip/lib/armeabi-v7a
	cp -a baresip/include distribution/baresip/
	cp -a baresip/libbaresip.a distribution/baresip/lib/armeabi-v7a/
	
	mkdir -p distribution/openssl
	mkdir -p distribution/openssl/lib/armeabi-v7a
	cp -a openssl/include distribution/openssl/
	cp -a openssl/libssl.a distribution/openssl/lib/armeabi-v7a/
	cp -a openssl/libcrypto.a distribution/openssl/lib/armeabi-v7a/
	
	mkdir -p distribution/opus
	mkdir -p distribution/opus/lib/armeabi-v7a
	cp -a opus/include distribution/opus/
	cp -a opus/.libs/libopus.a distribution/opus/lib/armeabi-v7a/
	
	mkdir -p distribution/re
	mkdir -p distribution/re/lib/armeabi-v7a
	cp -a re/include distribution/re/
	cp -a re/libre.a distribution/re/lib/armeabi-v7a/
	
	mkdir -p distribution/rem
	mkdir -p distribution/rem/lib/armeabi-v7a
	cp -a rem/include distribution/rem/
	cp -a rem/librem.a distribution/rem/lib/armeabi-v7a/


#
# additional targets for `retest'
#

test: retest
.PHONY: retest
retest:		Makefile librem.a libre.a
	@rm -f retest/retest
	@make $@ -C retest $(COMMON_FLAGS) LIBRE_SO=$(PWD)/re \
		LIBREM_PATH=$(PWD)/rem
	$(ADB) push retest/retest $(TARGET_PATH)/retest
	$(ADB) push retest/data/. $(TARGET_PATH)/data
	$(ADB) shell "cd $(TARGET_PATH) && ./retest -r -v"
