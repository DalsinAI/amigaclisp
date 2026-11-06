# AmigaOS 3.x with GCC (CXX): no position-independent code (m68k-amigaos
# has no GOT), so no -fPIC/-fPIE, whatever a project asks for.
# Copyright (c) 2026 AmiCradle Team
set(CMAKE_CXX_COMPILE_OPTIONS_PIC "")
set(CMAKE_CXX_COMPILE_OPTIONS_PIE "")
set(CMAKE_CXX_LINK_OPTIONS_PIE "")
set(CMAKE_CXX_LINK_OPTIONS_NO_PIE "")
set(CMAKE_SHARED_LIBRARY_CXX_FLAGS "")
