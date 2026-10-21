#!/bin/sh
# Builds LocalTube and installs it for the current user (default ~/.local).
#   ./install.sh              build + install
#   ./install.sh --uninstall  remove the installed files
#   PREFIX=/opt/localtube ./install.sh
set -e
cd "$(dirname "$0")"
PREFIX="${PREFIX:-$HOME/.local}"

if [ "$1" = "--uninstall" ]; then
    if [ ! -f build/install_manifest.txt ]; then
        echo "Nothing to uninstall (build/install_manifest.txt not found)." >&2
        exit 1
    fi
    xargs -d '\n' rm -fv < build/install_manifest.txt
    update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
    exit 0
fi

# CMake's cache records absolute paths, so a moved or renamed source folder
# needs a fresh build directory.
if [ -f build/CMakeCache.txt ] && ! grep -qx "CMAKE_HOME_DIRECTORY:INTERNAL=$(pwd)" build/CMakeCache.txt \
    && ! grep -qx "CMAKE_HOME_DIRECTORY:INTERNAL=$(pwd -P)" build/CMakeCache.txt; then
    echo "Source folder was moved; starting a clean build."
    rm -rf build
fi

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX"
cmake --build build -j"$(nproc)"
cmake --install build
update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
gtk-update-icon-cache -q -t "$PREFIX/share/icons/hicolor" 2>/dev/null || true

echo
echo "Installed: $PREFIX/bin/localtube"
case ":$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *) echo "Note: $PREFIX/bin is not in your PATH." ;;
esac
