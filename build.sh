#!/usr/bin/sh -e

ANDROID_API=15
TOOLCHAIN=arm-linux-androideabi-4.9

##
## Dep. versions
##

PCAP_VER=1.7.2
LUA_VER=5.2.4
JSON_VER=0.12
NFNL_VER=1.0.1
NFQ_VER=1.0.2
BIND_VER=6.0

##
## This shouldn't need to be changed for a while ...
##

BASE_DIR=$PWD

# Find NDK
if [ -z {$ANDROID_NDK} ]; then
    ANDROID_NDK=/opt/android-ndk
    echo "Setting ANDROID_NDK to a default value: $ANDROID_NDK"
fi
if [ -d ${ANDROID_NDK} ]; then
    echo "Found Android NDK in $ANDROID_NDK"
else
    echo "$ANDROID_NDK does not appear to contain a NDK installation...Aborting."
    exit 1
fi

# Export toolchain
if [ -d ${TOOLCHAIN} ]; then
    echo "Re-using existing Android NDK toolchain found in '$TOOLCHAIN'"
else
    echo "Creating Android NDK toolchain in '$TOOLCHAIN'"
    mkdir ${TOOLCHAIN}
    sh $ANDROID_NDK/build/tools/make-standalone-toolchain.sh \
        --platform=android-$ANDROID_API \
        --toolchain=${TOOLCHAIN} \
        --install-dir=${TOOLCHAIN}
    if [ $? -ne 0 ]; then
	    echo "Failed to create the Android NDK Toolchain...Aborting."
        rm -rf ${TOOLCHAIN}
		exit 1
    fi
fi

# Update env. var
export CC=arm-linux-androideabi-gcc
export CXX=arm-linux-androideabi-g++
export RANLIB=arm-linux-androideabi-ranlib
export AR=arm-linux-androideabi-ar
export LD=arm-linux-androideabi-ld
export STRIP=arm-linux-androideabi-strip
export PATH=$PWD/$TOOLCHAIN/bin:$PATH

export CFLAGS="-Os -fPIE $CFLAGS"
export CXXFLAGS="-Os -fPIE $CXXFLAGS"
export LDFLAGS="-fPIE -pie $LDFLAGS"
# Build dependencies

build_dep() {
    FILE=$(eval "echo \${F$1}")
    if [ ! -e ${FILE} ]; then
        echo "Downloading $FILE"
        curl -L -o $FILE $(eval "echo \${$1_URL}")
    else
        echo "Skipping download of $FILE"
    fi

    DIR=$(eval "echo \${$1}")-$(eval "echo \${$1_VER}")
    if [ ! -d ${DIR} ]; then
        echo "Expanding to $DIR"
        mkdir ${DIR}
        tar -xf ${FILE} -C ${DIR} --strip-component=1
    else
        echo "$FILE is already uncompressed in $DIR"
    fi

    cd ${DIR}
    BUILD="$1_build"
    eval ${BUILD}
    cd $BASE_DIR
}

PCAP=libpcap
FPCAP=$PCAP-$PCAP_VER.tar.gz
PCAP_URL=http://www.tcpdump.org/release/$FPCAP
PCAP_build() {
    echo "Building $PCAP"
    ./configure --host=arm-linux --with-pcap=linux --disable-shared --prefix=$PWD
    make -j4
    make install
}

LUA=lua
FLUA=$LUA-$LUA_VER.tar.gz
LUA_URL=http://www.lua.org/ftp/$FLUA
LUA_build() {
    echo "Building $LUA"
    echo "Patching source"
    sed -i "s/(localeconv()->decimal_point\[0\])/\'.\'/" src/llex.c
    sed -i "s/-DLUA_USE_LINUX\" SYSLIBS=\"-Wl,-E -ldl -lreadline\"/-DLUA_USE_LINUX\" SYSLIBS=\"-Wl,-E -ldl\"/g" src/Makefile
    sed -i "s/CC= gcc/CC=$CC/" src/Makefile
    sed -i "s/AR= ar rcu/AR=$AR rcu/" src/Makefile
    sed -i "s/RANLIB= ranlib/RANLIB=$RANLIB/" src/Makefile
    sed -i "s/O2/Os -fPIE/" src/Makefile
    sed -i "s/#define LUA_USE_READLINE//g" src/luaconf.h
    make linux -j4
}

JSON=json-c
FJSON=$JSON-$JSON_VER.tar.gz
JSON_URL=https://github.com/json-c/json-c/tarball/$JSON-$JSON_VER
JSON_build() {
    echo "Building $JSON"
    ./configure \
        --host=arm-linux \
        --disable-shared \
        --prefix=$PWD \
        ac_cv_func_malloc_0_nonnull=yes \
        ac_cv_func_realloc_0_nonnull=yes
    make -j4
    make install
}

NFNL=libnfnetlink
FNFNL=$NFNL-$NFNL_VER.tar.bz2
NFNL_URL=http://www.netfilter.org/projects/libnfnetlink/files/$FNFNL
NFNL_build() {
    echo "Skipping $NFNL"
    # We don't want the sniffer on the phones
}

NFQ=libnetfilter_queue
FNFQ=$NFQ-$NFQ_VER.tar.bz2
NFQ_URL=http://www.netfilter.org/projects/libnetfilter_queue/files/$FNFQ
NFQ_build() {
    echo "Skipping $NFQ"
    # We don't want the sniffer on the phones
}

BIND=libbind
FBIND=$BIND-$BIND_VER.tar.gz
BIND_URL=http://ftp.isc.org/isc/libbind/$BIND_VER/$FBIND
BIND_build() {
    echo "Building $BIND"
    mkdir -p build
    STD_CDEFINES="-DS_IREAD=S_IRUSR -DS_IWRITE=S_IWUSR -DS_IEXEC=S_IXUSR" \
        ./configure \
        --host=arm-linux \
        --disable-shared \
        --prefix=$PWD/build \
        --with-randomdev=/dev/random
    make -j4
    make install
    rm build/include/bind/arpa/inet.h
}

mkdir -p usr/include/sys
echo "#include <sys/types.h>" > usr/include/sys/bitypes.h
export CFLAGS="$CFLAGS -I$BASE_DIR/usr/include"
export CXXFLAGS="$CXXFLAGS -I$BASE_DIR/usr/include"

for dep in PCAP LUA JSON NFNL NFQ BIND; do
    build_dep $dep
done

export CFLAGS="$CFLAGS -I$BASE_DIR/$BIND-$BIND_VER/build/include/bind"
export CXXFLAGS="$CXXFLAGS -I$BASE_DIR/$BIND-$BIND_VER/build/include/bind"
export LDFLAGS="$LDFLAGS -L$BASE_DIR/$BIND-$BIND_VER/build/lib"

# ifaddrs replacement
cd android-ifaddrs
echo "Building support lib for ifaddrs"
$CC -c -Os -fPIE -o ifaddrs.o ifaddrs.c
$AR rcs libifaddrs.a ifaddrs.o
cd $BASE_DIR

export CFLAGS="$CFLAGS -I$BASE_DIR/android-ifaddrs"
export CXXFLAGS="$CXXFLAGS -I$BASE_DIR/android-ifaddrs"
export LDFLAGS="$LDFLAGS -L$BASE_DIR/android-ifaddrs"
cd tracebox
./bootstrap.sh
./configure \
    --prefix=$BASE_DIR \
    --host=arm-linux \
    --disable-shared \
    --enable-static \
    --with-libpcap=$BASE_DIR/$PCAP-$PCAP_VER \
    --with-lua=$BASE_DIR/$LUA-$LUA_VER/src \
    --with-json=$BASE_DIR/$JSON-$JSON_VER \
    --with-libs="$BASE_DIR/$BIND-$BIND_VER/build/lib/libbind.a $BASE_DIR/android-ifaddrs/libifaddrs.a $BASE_DIR/$JSON-$JSON_VER/lib/lib$JSON.a"
make -j4
make install-strip
