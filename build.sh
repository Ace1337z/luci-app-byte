#!/bin/sh
# Build luci-app-byte for OpenWrt - produces BOTH package formats without a
# full OpenWrt build tree:
#   dist/luci-app-byte_1.0.0-r1_all.ipk      (opkg, ar archive)
#   dist/luci-app-byte-1.0.0-r1.apk          (apk, apk-tools mkpkg)
#
# The .apk is built with "apk mkpkg" - the same tool and the same invocation
# OpenWrt's include/package-pack.mk uses - so package metadata and layout
# match what the firmware's own feeds ship. apk-tools 3.x (APKv3) is required;
# a static build is fetched on first run (override with APK_URL/APK_BIN).
#
# Usage: ./build.sh            # both formats
#        ./build.sh ipk|apk    # one format
set -eu

REPO_ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$REPO_ROOT"

# ---- version from the Makefile, OpenWrt style ----
PKG_VERSION=$(sed -n 's/^PKG_VERSION:=//p' Makefile)
PKG_RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' Makefile | tr -d ' ')
# Deterministic archives: fixed mtime, sorted, no gzip timestamp.
# --mtime takes an epoch (@...) because a quoted "date time" string would be
# split into extra arguments by the unquoted variable expansion below.
TAR_OPTS="--numeric-owner --owner=0 --group=0 --sort=name --mtime=@1577836800"
# opkg wants "1.0.0-1", apk-tools wants "1.0.0-r1" - same release, its own
# revision syntax.
IPK_VERSION="${PKG_VERSION}-${PKG_RELEASE:-1}"
APK_VERSION="${PKG_VERSION}-r${PKG_RELEASE:-1}"
NAME=luci-app-byte

# ---- shared package metadata (ipk control + apk info) ----
MAINTAINER="Ace1337z"
DEPENDS="luci-base, rpcd, libubox, jsonfilter, ubus"
ARCH=all
DESC="Single LuCI page under Tools to install, wire, inspect and undo the AdGuard Home + PassWall2 DNS chain. Ships the vendored upstream installer, so no runtime network fetch."
URL="https://github.com/Ace1337z/luci-app-byte"

# ---- static apk-tools 3.x, fetched once (used for verification only) ----
APK_URL=${APK_URL:-https://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/apk-tools-static-3.0.9-r0.apk}
APK_BIN=${APK_BIN:-.tools/apk.static}
if [ ! -x "$APK_BIN" ]; then
	echo "fetching apk-tools-static ..." >&2
	mkdir -p .tools
	curl -fsSL --max-time 60 "$APK_URL" -o .tools/apkts3.apk
	mkdir -p .tools/apkts3
	tar -xzf .tools/apkts3.apk -C .tools/apkts3
	find .tools/apkts3 -name apk.static -exec install -m755 {} "$APK_BIN" \;
	rm -rf .tools/apkts3 .tools/apkts3.apk
fi

# ---- stage the payload: htdocs -> /www, root -> / (mirrors luci.mk) ----
stage() {
	rm -rf .build-stage
	mkdir -p .build-stage
	[ -d htdocs ] && cp -a htdocs/. .build-stage/www/
	cp -a root/. .build-stage/
	find .build-stage \( -name '.svn' -o -name '.#*' -o -name '*~' \) -exec rm -rf {} + 2>/dev/null || true
	# cp -a carries the checkout umask (0775 dirs on this box). Normalize so
	# the package is identical no matter who runs the build: dirs 0755,
	# files 0644, the three scripts keep 0755.
	find .build-stage -type d -exec chmod 755 {} +
	find .build-stage -type f -exec chmod 644 {} +
	chmod 755 .build-stage/usr/libexec/rpcd/byte \
		.build-stage/usr/libexec/luci-app-byte/agh-passwall2.sh \
		.build-stage/etc/uci-defaults/90-luci-app-byte
}

# ---- ipk: ar with debian-binary, control.tar.gz, data.tar.gz ----
build_ipk() {
	stage
	echo "== ipk: $NAME $IPK_VERSION"

	installed=$(find .build-stage -type f -print0 | xargs -0 stat -c%s |
		awk '{ s += $1 } END { printf "%d", int(s / 1024) + 1 }')

	mkdir -p dist .build-stage/CONTROL
	cat >.build-stage/CONTROL/control <<EOF
Package: $NAME
Version: $IPK_VERSION
Depends: $DEPENDS
Provides: $NAME
Source: $NAME
License: GPL-3.0-only
Section: luci
Maintainer: $MAINTAINER
Architecture: $ARCH
Installed-Size: $installed
Description: $DESC
EOF

	# Same postinst luci.mk generates for luci packages: drop the LuCI caches
	# and reload rpcd so the new ACL and ubus backend take effect at once.
	cat >.build-stage/CONTROL/postinst <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	exit 0
}
EOF
	chmod 755 .build-stage/CONTROL/postinst

	rm -f dist/"$NAME"_"$IPK_VERSION"_"$ARCH".ipk
	(
		cd .build-stage
		tar $TAR_OPTS --exclude=./CONTROL -cf - . | gzip -n -9 >data.tar.gz
		tar $TAR_OPTS -C CONTROL -cf - . | gzip -n -9 >control.tar.gz
		echo 2.0 >debian-binary
		ar -rcD ../dist/"$NAME"_"$IPK_VERSION"_"$ARCH".ipk \
			debian-binary control.tar.gz data.tar.gz
		rm -f data.tar.gz control.tar.gz debian-binary
	)
	rm -rf .build-stage/CONTROL
}

# ---- apk: apk-tools mkpkg (APKv3), same invocation shape as OpenWrt's
# ---- include/package-pack.mk. Verified by apk verify + real install in a
# ---- scratch root: dexps must be space-separated words, not comma-joined.
build_apk() {
	stage
	echo "== apk: $NAME $APK_VERSION"
	mkdir -p dist

	cat >.tools/post-install <<'EOF'
#!/bin/sh
rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload 2>/dev/null
exit 0
EOF
	chmod 755 .tools/post-install

	# SOURCE_DATE_EPOCH=0 is what package-pack.mk exports - keeps the apk
	# reproducible across builds.
	SOURCE_DATE_EPOCH=0 "$APK_BIN" mkpkg \
		--info "name:$NAME" \
		--info "version:$APK_VERSION" \
		--info "arch:noarch" \
		--info "description:$DESC" \
		--info "license:GPL-3.0-only" \
		--info "origin:$NAME" \
		--info "maintainer:$MAINTAINER" \
		--info "url:$URL" \
		--info "depends:luci-base rpcd libubox jsonfilter ubus" \
		--script "post-install:.tools/post-install" \
		--files .build-stage \
		--output dist/"$NAME"-"$APK_VERSION".apk
}

case "${1:-all}" in
ipk) build_ipk ;;
apk) build_apk ;;
all) build_ipk && build_apk ;;
*) echo "usage: $0 [ipk|apk]" >&2; exit 2 ;;
esac

rm -rf .build-stage
echo
ls -l dist/
