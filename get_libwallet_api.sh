#!/bin/bash
WAZN_URL=https://github.com/project-wazn/wazn.git
WAZN_BRANCH=master

pushd $(pwd)
ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $ROOT_DIR/utils.sh

INSTALL_DIR=$ROOT_DIR/wallet
WAZN_DIR=$ROOT_DIR/wazn
BUILD_LIBWALLET=false

# init and update wazn submodule
if [ ! -d $WAZN_DIR/src ]; then
    git submodule init wazn
fi
git submodule update --remote
git -C $WAZN_DIR fetch
git -C $WAZN_DIR checkout master

# get WAZN core tag
pushd $WAZN_DIR
get_tag
popd
# create local WAZN branch
git -C $WAZN_DIR checkout -B $VERSIONTAG

git -C $WAZN_DIR submodule init
git -C $WAZN_DIR submodule update

# Merge WAZN PR dependencies

# Workaround for git username requirements
# Save current user settings and revert back when we are done with merging PR's
OLD_GIT_USER=$(git -C $WAZN_DIR config --local user.name)
OLD_GIT_EMAIL=$(git -C $WAZN_DIR config --local user.email)
git -C $WAZN_DIR config user.name "vermin"
git -C $WAZN_DIR config user.email "vermin@techie.com"
# check for PR requirements in most recent commit message (i.e requires #xxxx)
for PR in $(git log --format=%B -n 1 | grep -io "requires #[0-9]*" | sed 's/[^0-9]*//g'); do
    echo "Merging WAZN push request #$PR"
    # fetch pull request and merge
    git -C $WAZN_DIR fetch origin pull/$PR/head:PR-$PR
    git -C $WAZN_DIR merge --quiet PR-$PR  -m "Merge WAZN PR #$PR"
    BUILD_LIBWALLET=true
done

# revert back to old git config
$(git -C $WAZN_DIR config user.name "$OLD_GIT_USER")
$(git -C $WAZN_DIR config user.email "$OLD_GIT_EMAIL")

# Build libwallet if it doesnt exist
if [ ! -f $WAZN_DIR/lib/libwallet_merged.a ]; then
    echo "libwallet_merged.a not found - Building libwallet"
    BUILD_LIBWALLET=true
# Build libwallet if no previous version file exists
elif [ ! -f $WAZN_DIR/version.sh ]; then
    echo "wazn/version.h not found - Building libwallet"
    BUILD_LIBWALLET=true
## Compare previously built version with submodule + merged PR's version.
else
    source $WAZN_DIR/version.sh
    # compare submodule version with latest build
    pushd "$WAZN_DIR"
    get_tag
    popd
    echo "latest libwallet version: $GUI_WAZN_VERSION"
    echo "Installed libwallet version: $VERSIONTAG"
    # check if recent
    if [ "$VERSIONTAG" != "$GUI_WAZN_VERSION" ]; then
        echo "Building new libwallet version $GUI_WAZN_VERSION"
        BUILD_LIBWALLET=true
    else
        echo "latest libwallet ($GUI_WAZN_VERSION) is already built. Remove wazn/lib/libwallet_merged.a to force rebuild"
    fi
fi

if [ "$BUILD_LIBWALLET" != true ]; then
    exit 0
fi

echo "GUI_WAZN_VERSION=\"$VERSIONTAG\"" > $WAZN_DIR/version.sh

## Continue building libwallet

# default build type
BUILD_TYPE=$1
if [ -z $BUILD_TYPE ]; then
    BUILD_TYPE=release
fi

STATIC=false
ANDROID=false
if [ "$BUILD_TYPE" == "release" ]; then
    echo "Building libwallet release"
    CMAKE_BUILD_TYPE=Release
elif [ "$BUILD_TYPE" == "release-static" ]; then
    echo "Building libwallet release-static"
    CMAKE_BUILD_TYPE=Release
    STATIC=true
elif [ "$BUILD_TYPE" == "release-android" ]; then
    echo "Building libwallet release-static for ANDROID"
    CMAKE_BUILD_TYPE=Release
    STATIC=true
    ANDROID=true
elif [ "$BUILD_TYPE" == "debug-android" ]; then
    echo "Building libwallet debug-static for ANDROID"
    CMAKE_BUILD_TYPE=Debug
    STATIC=true
    ANDROID=true
elif [ "$BUILD_TYPE" == "debug" ]; then
    echo "Building libwallet debug"
    CMAKE_BUILD_TYPE=Debug
    STATIC=true
else
    echo "Valid build types are release, release-static, release-android, debug-android and debug"
    exit 1;
fi


echo "cleaning up existing WAZN build dir, libs and includes"
rm -fr $WAZN_DIR/build
rm -fr $WAZN_DIR/lib
rm -fr $WAZN_DIR/include
rm -fr $WAZN_DIR/bin


mkdir -p $WAZN_DIR/build/$BUILD_TYPE
pushd $WAZN_DIR/build/$BUILD_TYPE

# reusing function from "utils.sh"
platform=$(get_platform)
# default make executable
make_exec="make"

## OS X
if [ "$platform" == "darwin" ]; then
    echo "Configuring build for MacOS.."
    if [ "$STATIC" == true ]; then
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D ARCH="x86-64" -D BUILD_64=ON -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    else
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE  -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    fi

## LINUX 64
elif [ "$platform" == "linux64" ]; then
    echo "Configuring build for Linux x64"
    if [ "$ANDROID" == true ]; then
        echo "Configuring build for Android on Linux host"
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D ARCH="armv7-a" -D ANDROID=true -D BUILD_GUI_DEPS=ON -D USE_LTO=OFF -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    elif [ "$STATIC" == true ]; then
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D ARCH="x86-64" -D BUILD_64=ON -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    else
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    fi

## LINUX 32
elif [ "$platform" == "linux32" ]; then
    echo "Configuring build for Linux i686"
    if [ "$STATIC" == true ]; then
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D ARCH="i686" -D BUILD_64=OFF -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    else
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    fi

## LINUX ARMv7
elif [ "$platform" == "linuxarmv7" ]; then
    echo "Configuring build for Linux armv7"
    if [ "$STATIC" == true ]; then
        cmake -D BUILD_TESTS=OFF -D ARCH="armv7-a" -D STATIC=ON -D BUILD_64=OFF  -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    else
        cmake -D BUILD_TESTS=OFF -D ARCH="armv7-a" -D -D BUILD_64=OFF  -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    fi

## LINUX other
elif [ "$platform" == "linux" ]; then
    echo "Configuring build for Linux general"
    if [ "$STATIC" == true ]; then
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    else
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    fi

## Windows 64
## Windows is always static to work outside msys2
elif [ "$platform" == "mingw64" ]; then
    # Do something under Windows NT platform
    echo "Configuring build for MINGW64.."
    BOOST_ROOT=/mingw64/boost
    cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D BOOST_ROOT="$BOOST_ROOT" -D ARCH="x86-64" -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR" -G "MSYS Makefiles" -D CMAKE_TOOLCHAIN_FILE=../../cmake/64-bit-toolchain.cmake -D MSYS2_FOLDER=c:/msys64 ../..

## Windows 32
elif [ "$platform" == "mingw32" ]; then
    # Do something under Windows NT platform
    echo "Configuring build for MINGW32.."
    BOOST_ROOT=/mingw32/boost
    cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D Boost_DEBUG=ON -D BOOST_ROOT="$BOOST_ROOT" -D ARCH="i686" -D BUILD_64=OFF -D BUILD_GUI_DEPS=ON -D INSTALL_VENDORED_LIBUNBOUND=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR" -G "MSYS Makefiles" ../..
    make_exec="mingw32-make"
else
    echo "Unknown platform, configuring general build"
    if [ "$STATIC" == true ]; then
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D STATIC=ON -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    else
        cmake -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE -D BUILD_GUI_DEPS=ON -D CMAKE_INSTALL_PREFIX="$WAZN_DIR"  ../..
    fi
fi

# set CPU core count
# thanks to SO: http://stackoverflow.com/a/20283965/4118915
if test -z "$CPU_CORE_COUNT"; then
  CPU_CORE_COUNT=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu)
fi

# Build libwallet_merged
pushd $WAZN_DIR/build/$BUILD_TYPE/src/wallet
eval $make_exec version -C ../..
eval $make_exec  -j$CPU_CORE_COUNT
eval $make_exec  install -j$CPU_CORE_COUNT
popd

# Build waznd
# win32 need to build daemon manually with msys2 toolchain
if [ "$platform" != "mingw32" ] && [ "$ANDROID" != true ]; then
    pushd $WAZN_DIR/build/$BUILD_TYPE/src/daemon
    eval make  -j$CPU_CORE_COUNT
    eval make install -j$CPU_CORE_COUNT
    popd
fi

# build install epee
eval make -C $WAZN_DIR/build/$BUILD_TYPE/contrib/epee all install

# install easylogging
eval make -C $WAZN_DIR/build/$BUILD_TYPE/external/easylogging++ all install

# install lmdb
eval make -C $WAZN_DIR/build/$BUILD_TYPE/external/db_drivers/liblmdb all install

# Install libunbound
echo "Installing libunbound..."
pushd $WAZN_DIR/build/$BUILD_TYPE/external/unbound
# no need to make, it was already built as dependency for libwallet
# make -j$CPU_CORE_COUNT
$make_exec install -j$CPU_CORE_COUNT
popd


popd
