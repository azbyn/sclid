THIS_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

D_SRC_DIR   := dlang
D_BUILD_DIR := build/obj
D_TARGET    := libsclid.so
DC          := dmd
D_FLAGS     := -g -gf -gs -debug -fPIC -I=${D_SRC_DIR}


D_SRCS      := $(shell find $(D_SRC_DIR) -name \*.d)
D_OBJS      := $(D_SRCS:%.d=$(D_BUILD_DIR)/%.o)

D_LIB_DIR  := ../sclid-patched-libs
D_LIB_TYPE := linux/release/64

D_LD_FLAGS  := -L=-lsqlite3 -L=-ldbus-1

# uses a different version system
SIGNAL_CLI_VERSION := 0.6.8
EXECUTABLE := build/install/sclid/bin/sclid

default: build

buildAndRun: build run

buildAndRunD: buildD run

.PHONY: build buildJava buildD run buildAndRun cleanD
buildJava:
	./gradlew build
	./gradlew installDist
	./gradlew distTar

install:
	tar xf build/distributions/sclid-${SIGNAL_CLI_VERSION}.tar -C /opt
	ln -sf /opt/sclid-${SIGNAL_CLI_VERSION}/bin/sclid /usr/local/bin
	cp ${D_TARGET} /usr/lib

echo:
	@echo ${D_SRCS}
	@echo ${D_OBJS}

buildD: ${D_TARGET}

${D_TARGET}: ${D_SRCS}
	dmd ${D_FLAGS} ${D_LD_FLAGS} -shared -of=$@ -od=${D_BUILD_DIR} -op ${D_SRCS}

cleanD:
	@rm -rf -v ${D_BUILD_DIR}
	rm ${D_TARGET}

MKDIR_P ?= mkdir -p

build: buildD buildJava
run:
	./${EXECUTABLE}
