TARGET       := $(shell $(CC) -dumpmachine)
CFLAGS       := -Wall -Werror \
                -O3 -ffast-math

NO_NATIVE   := $(shell $(CC) -E - </dev/null >/dev/null 2>&1 -march=native; echo $$?)
NO_FPMATH   := $(shell $(CC) -E - </dev/null >/dev/null 2>&1 -mfpmath=sse;  echo $$?)
NO_SSSE3    := $(shell $(CC) -E - </dev/null >/dev/null 2>&1 -mssse3;       echo $$?)
NO_AVX_FLAG := $(shell $(CC) -E - </dev/null >/dev/null 2>&1 -mavx;         echo $$?)

ifeq ($(NO_NATIVE), 0)
  CFLAGS += -march=native
endif
ifeq ($(NO_FPMATH), 0)
  CFLAGS += -mfpmath=sse
endif
ifeq ($(NO_SSSE3), 0)
  CFLAGS += -mno-ssse3
endif
ifeq ($(NO_AVX_FLAG), 0)
  CFLAGS += -mno-avx
endif

ifneq (,$(findstring mingw,$(TARGET))$(findstring cygwin,$(TARGET)))
  CFLAGS += -mstackrealign
endif
