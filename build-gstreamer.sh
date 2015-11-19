#!/bin/bash
# Copyright 2014-2015 Mikhail Afanasyev.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


print_help() {
    cat <<EOF
Usage: $1 command [command1..]
This script builds gstreamer from source and packs it into tar.gz file.

Commands:
  deps      -- use apt-get to install build deps

  download  -- download source tars (automatic with configure)
  configure -- wipe workdir, re-extract, and run ./configure
  makeinstall -- run make, then makeinstall
  tar       -- tar up the result
  clean     -- wipe workdirs (always done last)
  all       -- download + configure + makeinstall + tar
  allclean  -- do all + clean

  some      -- limit actions to subset of components (see source)

Script should say 'Success' at the last line, or there is an error.
EOF
}

# Version to build
#VER=1.2.4
#VER=1.4.4
VER=1.4.5

# where to install
GST_PREFIX=/opt/gstreamer-$VER

# script revision. Should be updated every time build options change
REVISION=1

# where to put tar file
# (note the revision number)
FINAL_TAR=tars/mj-gstreamer-$VER-$(uname -m)-$(lsb_release -c -s).tar.bz2

# Temporary bulding space. Normally in /tmp, but you can pre-create
# directory and it will be build there.
for BUILD_DIR in $HOME/gst-build-$VER /tmp/gst-build-$VER; do
    if test -d $BUILD_DIR; then
        break
    fi
done

set -e

echo Building gstreamer $VER in $BUILD_DIR, will install to $GST_PREFIX
echo Will pack to $FINAL_TAR

COMPONENTS="gstreamer plugins-base "
COMPONENTS+="plugins-good plugins-bad plugins-ugly rtsp-server libav"

do_deps=0
do_download=0
do_configure=0
do_makeinstall=0
do_tar=0
do_clean=0
do_components="$COMPONENTS"

while [[ "$1" != "" ]]; do
    case "$1" in
        deps)
            do_deps=1
            ;;
        download)
            do_download=1
            ;;
        configure)
            do_download=1
            do_configure=1
            ;;
        makeinstall)
            do_makeinstall=1
            ;;
        tar)
            do_tar=1
            ;;
        clean)
            do_clean=1
            ;;
        all)
            do_download=1
            do_configure=1
            do_makeinstall=1
            do_tar=1
            ;;
        allclean)
            do_download=1
            do_configure=1
            do_makeinstall=1
            do_tar=1
            do_clean=1
            ;;
        some)
            do_components="rtsp-server"
            ;;
        *)
            echo Invalid option
            print_help
            exit 1
            ;;
    esac
    shift
done

if [[ "$do_deps" == 1 ]]; then
    (set -x;
        sudo apt-get build-dep gstreamer1.0 gstreamer1.0-plugins-good \
            gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
            gstreamer1.0-plugins-base gstreamer1.0-libav
    )
    exit
fi

if [[ "$do_makeinstall" == 1 ]]; then
    if ! mkdir -p $GST_PREFIX; then
        echo Permission denied to $GST_PREFIX. Try:
        echo ' ' sudo install -o $(id -un) -d $GST_PREFIX
        exit 1
    fi
fi

umask 0022

make_log_file() {
    local component=$1
    local step=$2
    local log_name=$BUILD_DIR/log-$step-$component.txt
    echo Doing $step to $component, log in $log_name >&2
    ln -fs $(basename $log_name) $BUILD_DIR/log-latest.txt
    echo $log_name
}

dirs_to_clean=""
for component in $do_components; do
    if [[ $component == gstreamer ]]; then
        build_base=gstreamer-$VER
        url=http://gstreamer.freedesktop.org/src/gstreamer/$build_base.tar.xz
    else
        build_base=gst-$component-$VER
        url=http://gstreamer.freedesktop.org/src/gst-$component/$build_base.tar.xz
    fi
    tar_name=$BUILD_DIR/tars/$build_base.tar.xz
    build_full=$BUILD_DIR/$build_base
    dirs_to_clean+="$build_full "

    # Download
    if [[ "$do_download" == "1" && ! -f "$tar_name" ]]; then
        mkdir -p $BUILD_DIR/tars
        tmpfile=$BUILD_DIR/download.temp
        wget -O "$tmpfile" "$url" 1>&2 || exit 1
        xz -t "$tmpfile" || exit 1
        mv "$tmpfile" "$tar_name"
    fi

    # Extract/configure
    if [[ "$do_configure" == "1" ]]; then
        if [[ -d $build_full ]]; then
            echo Wiping old contents of $build_base
            rm -r $build_full
        fi
        echo -n 'Extracting: '
        # 'mkdir' and 'du -hs' to detect undeleted data/bad extraction
        (
            cd $BUILD_DIR && mkdir $build_base && tar -xJf $tar_name \
                && du -hs $build_base
        ) >&2

        config_args=""
        if [[ "$component" != gstreamer ]]; then
            config_args="--with-x"
        fi
        log_name=$(make_log_file $component config)
        (set -x;
            export PKG_CONFIG_PATH=$GST_PREFIX/lib/pkgconfig
            cd $build_full
            ./configure --prefix=$GST_PREFIX $config_args
        ) >$log_name 2>&1
    fi

    # Make and install
    if [[ "$do_makeinstall" == "1" ]]; then
        log_name=$(make_log_file $component make)
        (set -x;
            export PKG_CONFIG_PATH=$GST_PREFIX/lib/pkgconfig
            cd $build_full
            make && make install
        ) >$log_name 2>&1
    fi
    echo
done

if [[ "$do_makeinstall" == "1" && "$do_components" == "$COMPONENTS" ]]; then
    # mark this compile are successful by creating revision file
    echo $REVISION > $GST_PREFIX/mj-gstreamer-revision
fi

if [[ "$do_tar" == "1" ]]; then
    if ! test -f $GST_PREFIX/mj-gstreamer-revision; then
        echo Refusing to build tar -- looks like makeinstall did not finish
        exit 1
    fi
    mkdir -p $(dirname $FINAL_TAR)
    rm -f $FINAL_TAR
    tar cjf $FINAL_TAR --owner=root --group=root -C / ${GST_PREFIX#/}
    ls -lh $FINAL_TAR
fi

if [[ "$do_clean" == "1" ]]; then
    echo Cleaning build directories
    (set -x;
        rm -rf $dirs_to_clean
        )
fi

echo Success
