#!/bin/bash

set -e

# Adopt a Unix-friendly path if we're on Windows (see bld.bat).
[ -n "$PATH_OVERRIDE" ] && export PATH="$PATH_OVERRIDE"

# On Windows we want $LIBRARY_PREFIX in both "mixed" (C:/Conda/...) and Unix
# (/c/Conda) forms, but Unix form is often "/" which can cause problems.
if [ -n "$LIBRARY_PREFIX_M" ] ; then
    mprefix="$LIBRARY_PREFIX_M"
    if [ "$LIBRARY_PREFIX_U" = / ] ; then
        uprefix=""
    else
        uprefix="$LIBRARY_PREFIX_U"
    fi
else
    mprefix="$PREFIX"
    uprefix="$PREFIX"
fi

configure_args=(
    --prefix=$mprefix
    --disable-static
    --disable-dependency-tracking
    --disable-selective-werror
    --disable-silent-rules
)

# On Windows we need to regenerate the configure scripts.
if [ -n "$CYGWIN_PREFIX" ] ; then
    export ACLOCAL=aclocal-$am_version
    export AUTOMAKE=automake-$am_version
    autoreconf_args=(
        --force
        --install
        -I "$mprefix/share/aclocal"
        -I "$BUILD_PREFIX_M/Library/usr/share/aclocal"
    )
    autoreconf "${autoreconf_args[@]}"

    export CC="gcc"
    
    # And we need to add the search path that lets libtool find the
    # msys2 stub libraries for ws2_32.
    # Find MSYS2 libraries directory using a more reliable approach
    platlibs=""
    for potential_path in \
        "$(dirname $($CC --print-prog-name=ld))/../sysroot/usr/lib" \
        "$(dirname $($CC --print-prog-name=ld))/../x86_64-w64-mingw32/lib" \
        "$BUILD_PREFIX_M/Library/mingw-w64/lib" \
        "$BUILD_PREFIX_M/Library/usr/lib" \
        "$BUILD_PREFIX_M/Library/x86_64-w64-mingw32/sysroot/usr/lib"; do
        if [ -f "$(cygpath -u "$potential_path")/libws2_32.a" ]; then
            platlibs=$(cygpath -u "$potential_path")
            break
        fi
    done

    # Check for winpthread in standard locations
    for lib in libwinpthread libpthread_win32 libpthread; do
        if [ -f "$BUILD_PREFIX_M/Library/lib/${lib}.a" ] || [ -f "$BUILD_PREFIX_M/Library/lib/${lib}.dll.a" ]; then
        export PTHREAD_LIBS="-l${lib#lib}"
        break
        fi
    done
    
    # Override pthread flags for Windows
    export LDFLAGS="$LDFLAGS $PTHREAD_LIBS"
    # Patch configuration if needed
    sed -i 's/-lpthread/'"$PTHREAD_LIBS"'/g' configure || true
    
    if [ -f "$platlibs/libws2_32.a" ]; then
        export LDFLAGS="$LDFLAGS -L$platlibs"
    else
        echo "Warning: Could not find libws2_32.a"
    fi
else
    # Get an updated config.sub and config.guess
    cp $BUILD_PREFIX/share/gnuconfig/config.* .

    autoreconf_args=(
        --force
        --install
        -I "${PREFIX}/share/aclocal"
        -I "${BUILD_PREFIX}/share/aclocal"
    )
    autoreconf "${autoreconf_args[@]}"

    configure_args+=("--build=${BUILD}")
fi

export PKG_CONFIG_LIBDIR=$uprefix/lib/pkgconfig:$uprefix/share/pkgconfig

if [[ "${CONDA_BUILD_CROSS_COMPILATION}" == "1" ]] ; then
    configure_args+=(
        --enable-malloc0returnsnull
    )
fi

./configure "${configure_args[@]}"
make -j$CPU_COUNT
make install

rm -rf $uprefix/share/man $uprefix/share/doc/${PKG_NAME#xorg-}
