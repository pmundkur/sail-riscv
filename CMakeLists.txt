cmake_minimum_required(VERSION 3.20)
cmake_policy(VERSION 3.20...3.31)

# CMake 3.24 and newer don't use the mtimes from archives when extracting
# GMP in ExternalProject_Add(). This reverts that behaviour so that the
# mtimes in the archive are used. This is necessary because otherwise
# Make tries to rebuild the documentation that is already built, and
# this requires `makeinfo` which we don't want to require.
# TODO: Remove this when we bump the minimum CMake version to 3.24 and
# instead add DOWNLOAD_EXTRACT_TIMESTAMP TRUE to ExternalProject_Add().
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 OLD)
endif()

include(cmake/project_version.cmake)
project(sail-riscv
  VERSION ${sail_riscv_release_version}
  HOMEPAGE_URL "https://github.com/riscv/sail-riscv"
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED TRUE)
set(SAIL_REQUIRED_VER 0.19.1)

# Make users explicitly pick a build type so they don't get
# surprised when the default gives a very slow emulator.
if (NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    message(FATAL_ERROR "
No build type selected. You need to pass -DCMAKE_BUILD_TYPE=<type> in order to configure the build.
    * -DCMAKE_BUILD_TYPE=Release        - Optimized build with no debug info.
    * -DCMAKE_BUILD_TYPE=RelWithDebInfo - Optimized build with debug info.
    * -DCMAKE_BUILD_TYPE=Debug          - Unoptimized build with debug info.
    * -DCMAKE_BUILD_TYPE=MinSizeRel     - Optimized for size instead of speed.")
endif()

# Enable CTest
enable_testing()

# Export compile_commands.json for IDE support.
set(CMAKE_EXPORT_COMPILE_COMMANDS TRUE)

# Always use Position Independent Code. By default it is only used for
# shared libraries (which require it), but you also need it for static
# libraries if you link them into shared libraries.
# Generally it just simplifies everything for a negligible performance cost.
set(CMAKE_POSITION_INDEPENDENT_CODE TRUE)

# Don't allow undefined symbols. This is generally a pain.
include(CheckLinkerFlag)

check_linker_flag(C "-Wl,--no-undefined" LINKER_SUPPORTS_NO_UNDEFINED)
if (LINKER_SUPPORTS_NO_UNDEFINED)
    add_link_options("-Wl,--no-undefined")
endif()

add_compile_options(-Wall -Wextra -Wno-sign-compare)
include(CheckCCompilerFlag)
check_c_compiler_flag(-Wimplicit-fallthrough HAVE_WIMPLICIT_FALLTHROUGH)

# Ensure we globally build with assertions enabled even in non-Debug
# builds, following the approach of LLVM in
#   llvm/cmake/modules/HandleLLVMOptions.cmake
string(TOUPPER "${CMAKE_BUILD_TYPE}" uppercase_CMAKE_BUILD_TYPE)
# On non-Debug builds cmake automatically defines NDEBUG; so
# explicitly undefine it:
if(NOT uppercase_CMAKE_BUILD_TYPE STREQUAL "DEBUG")
    add_compile_options($<$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>:-UNDEBUG>)
endif()

# Extra CMake files.
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules")

# This will change how the `find_library` calls work so they find
# the static version of libraries first. Unlike `-static` it won't
# link glibc statically, which is generally considered to be a bad idea.
option(STATIC "Prefer static versions of dependencies.")

if (STATIC)
    if (WIN32)
        list(INSERT CMAKE_FIND_LIBRARY_SUFFIXES 0 .lib .a)
    else()
        set(CMAKE_FIND_LIBRARY_SUFFIXES .a)
        check_linker_flag(CXX "-static-libstdc++" HAVE_STATIC_LIBSTDCXX)
        if (NOT HAVE_STATIC_LIBSTDCXX)
            message(FATAL_ERROR "Building with -DSTATIC=TRUE requires static C++ std library installation")
        endif()
        add_link_options(-static-libstdc++)
        check_linker_flag(CXX "-static-libgcc" HAVE_STATIC_LIBGCC)
        if (NOT HAVE_STATIC_LIBGCC)
            message(FATAL_ERROR "Building with -DSTATIC=TRUE requires static libgcc installation")
        endif()
        add_link_options(-static-libgcc)
    endif()
endif()


# These are the main requirements.

find_program(SAIL_BIN "sail")
if (NOT SAIL_BIN)
    message(FATAL_ERROR "Sail not found. See README.md for installation instructions.")
endif()
message(STATUS "Found sail: ${SAIL_BIN}")

# Set sail_dir to Sail's library directory for use in build rules
execute_process(
    COMMAND ${SAIL_BIN} --dir
    OUTPUT_VARIABLE sail_dir
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)
message(STATUS "Sail library directory: ${sail_dir}")

option(COVERAGE "Compile with Sail coverage collection enabled.")

include(GNUInstallDirs)

# Third party dependencies.
add_subdirectory("dependencies")

# Sail C runtime.
add_subdirectory("sail_runtime")

# Sail configuration
add_subdirectory("config")

# Sail model generated C code.
add_subdirectory("model")

# Emulator binary.
add_subdirectory("c_emulator")

# Old pre-compiled riscv-tests & first-party tests.
add_subdirectory("test")

# Handwritten support files for provers
add_subdirectory("handwritten_support")

# Convenience targets.
add_custom_target(csim DEPENDS sail_riscv_sim)
add_custom_target(check DEPENDS generated_model_rv)

# TODO: Add `interpret` target.
# TODO: Add hol4 target.

# Release packaging.
include(cmake/packaging.cmake)
