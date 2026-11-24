# shellcheck shell=bash disable=SC2034
TERMUX_PKG_HOMEPAGE=https://github.com/AnInsomniacy/aria2-next
TERMUX_PKG_DESCRIPTION="Maintained fork of the aria2 download utility"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@Hussain-Najeb"
TERMUX_PKG_VERSION=3.0.10
TERMUX_PKG_SRCURL=git+https://github.com/AnInsomniacy/aria2-next
TERMUX_PKG_GIT_BRANCH="v${TERMUX_PKG_VERSION}"
_COMMIT=6148910b42fd472e5155fb4539a18740df24e97d
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_DEPENDS="libc++, openssl, libsqlite, libexpat, zlib"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DARIA2_RELEASE_SIZE_OPTIMIZED=ON
-DARIA2_RELEASE_LTO=ON
"

termux_step_post_get_source() {
    if [ "$(git rev-parse HEAD)" != "$_COMMIT" ]; then
        git fetch --depth 1 origin "$_COMMIT"
        git checkout --force "$_COMMIT"
    fi
    [ "$(git rev-parse HEAD)" = "$_COMMIT" ] || termux_error_exit "aria2-next source does not match pinned commit $_COMMIT"
}

termux_step_pre_configure() {
    CFLAGS="${CFLAGS:-} -Oz -ffunction-sections -fdata-sections -flto=thin"
    CXXFLAGS="${CXXFLAGS:-} -Oz -ffunction-sections -fdata-sections -flto=thin"
    LDFLAGS="${LDFLAGS:-} -flto=thin -fuse-ld=lld -Wl,--gc-sections -Wl,--icf=safe -Wl,--pack-dyn-relocs=android"

    local prebuilt_ffmpeg="${TERMUX_PKG_BUILDER_DIR:-}/.ffmpeg-prebuilt/${TERMUX_ARCH:-}"
    if [ -d "$prebuilt_ffmpeg/include" ] && [ -d "$prebuilt_ffmpeg/lib" ]; then
        TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" -DARIA2_PREBUILT_FFMPEG_DIR=$prebuilt_ffmpeg"
        LDFLAGS+=" -Wl,-rpath-link,$prebuilt_ffmpeg/lib"
    fi

    if [ -d "${TERMUX_PREFIX:-}/include/openssl" ] && [ -f "${TERMUX_PREFIX:-}/lib/libcrypto.so" ]; then
        TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" -DARIA2_SYSTEM_DEPS_PREFIX=$TERMUX_PREFIX"
        LDFLAGS+=" -Wl,-rpath-link,$TERMUX_PREFIX/lib"
    fi
}

termux_step_make_install() {
	install -Dm700 "$TERMUX_PKG_BUILDDIR/aria2-next" "$TERMUX_PREFIX/bin/aria2-next"
}
