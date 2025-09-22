# Don't use `REQUIRED` so that we can print custom help messages.
option(DOWNLOAD_GMP "Download libgmp and build the library locally instead of using a system installation" OFF)
if (DOWNLOAD_GMP)
    include(ExternalProject)
    ExternalProject_Add(
        gmp
        URL https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz https://ftpmirror.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz
        URL_HASH SHA256=a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898
        INSTALL_DIR ${CMAKE_CURRENT_BINARY_DIR}/gmp
        CONFIGURE_COMMAND "<SOURCE_DIR>/configure" "--prefix=<INSTALL_DIR>" --disable-shared --enable-static --with-pic
        # The libgmp.a output is created by the install step but since GMP::GMP
        # depends on the entire ExternalProject build, we can pretend it is
        # created by the build.
        # TODO: Once we depend on CMake 3.26, use INSTALL_BYPRODUCTS
        BUILD_BYPRODUCTS "<INSTALL_DIR>/lib/libgmp.a"
    )
    ExternalProject_Get_property(gmp INSTALL_DIR)
    add_library(GMP::GMP STATIC IMPORTED GLOBAL)
    # Work around `Imported target "GMP::GMP" includes non-existent path`.
    # See https://gitlab.kitware.com/cmake/cmake/-/issues/15052
    file(MAKE_DIRECTORY ${INSTALL_DIR}/include)
    set_target_properties(GMP::GMP PROPERTIES
            IMPORTED_LOCATION "${INSTALL_DIR}/lib/libgmp.a"
            INTERFACE_INCLUDE_DIRECTORIES "${INSTALL_DIR}/include")
    add_dependencies(GMP::GMP gmp)
else()
    find_package(GMP)
    if (NOT GMP_FOUND)
        set(download_gmp "setting -DDOWNLOAD_GMP=TRUE to use a local build of GMP instead of a system library")
        if (APPLE)
            message(FATAL_ERROR "GMP not found. Try 'brew install gmp' or ${download_gmp}.")
        elseif (UNIX)
            message(FATAL_ERROR "GMP not found. Try 'sudo apt install libgmp-dev' or 'sudo dnf install gmp-devel' or ${download_gmp}.")
        else()
            message(FATAL_ERROR "GMP not found. Try ${download_gmp}")
        endif()
    endif()
endif()
