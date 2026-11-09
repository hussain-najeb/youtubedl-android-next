TERMUX_PKG_HOMEPAGE=https://github.com/AnInsomniacy/aria2-next
TERMUX_PKG_DESCRIPTION="Maintained fork of the aria2 download utility"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@Hussain-Najeb"
TERMUX_PKG_VERSION=3.0.10
TERMUX_PKG_SRCURL=git+https://github.com/AnInsomniacy/aria2-next
TERMUX_PKG_GIT_BRANCH="v${TERMUX_PKG_VERSION}"
_COMMIT=6148910b42fd472e5155fb4539a18740df24e97d
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_DEPENDS="libc++"

termux_step_post_get_source() {
    git fetch --unshallow
    git checkout "$_COMMIT"
    [ "$(git rev-parse HEAD)" = "$_COMMIT" ] || termux_error_exit "aria2-next source does not match pinned commit $_COMMIT"
}

termux_step_make_install() {
	install -Dm700 "$TERMUX_PKG_BUILDDIR/aria2-next" "$TERMUX_PREFIX/bin/aria2-next"
}
