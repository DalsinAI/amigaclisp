# CMake toolchain for the 68040 AmigaOS build (soft float; the FPU when there
# is one, through fpuauto).
#   -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-m68k-amigaos.cmake -DAMIGA_TOOLCHAIN=...
#   -DAMIGA_SPECS=... [-DAMIGA_FPUSPECS=... -DAMIGA_FPULIB=...]
# Copyright (c) 2026 AmiCradle Team
set(CMAKE_SYSTEM_NAME AmigaOS)
set(CMAKE_SYSTEM_PROCESSOR m68k)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}")
set(CMAKE_C_COMPILER "${AMIGA_TOOLCHAIN}/bin/m68k-amigaos-gcc")
set(CMAKE_CXX_COMPILER "${AMIGA_TOOLCHAIN}/bin/m68k-amigaos-g++")
set(CMAKE_AR "${AMIGA_TOOLCHAIN}/bin/m68k-amigaos-ar" CACHE FILEPATH "")
set(CMAKE_RANLIB "${AMIGA_TOOLCHAIN}/bin/m68k-amigaos-ranlib" CACHE FILEPATH "")
set(CMAKE_STRIP "${AMIGA_TOOLCHAIN}/bin/m68k-amigaos-strip" CACHE FILEPATH "")
set(CMAKE_C_FLAGS_INIT "-noixemul -m68040")
set(CMAKE_CXX_FLAGS_INIT "-noixemul -m68040 -fno-delete-null-pointer-checks")
set(_amiga_ld "-noixemul -m68040 -specs=${AMIGA_SPECS}")
if(AMIGA_FPUSPECS)
  string(APPEND _amiga_ld " -specs=${AMIGA_FPUSPECS} -L${AMIGA_FPULIB}")
endif()
set(CMAKE_EXE_LINKER_FLAGS_INIT "${_amiga_ld}")
set(CMAKE_C_STANDARD_LIBRARIES "-lsocket -lpthread -latomic -lm")
set(CMAKE_CXX_STANDARD_LIBRARIES "-lsocket -lpthread -latomic -lm")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
