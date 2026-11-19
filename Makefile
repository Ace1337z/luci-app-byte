#
# Copyright (C) 2026 Ace1337z
#
# This is free software, licensed under the GNU General Public License v3.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-byte
PKG_VERSION:=1.0.4
# r2: byte.css resolves the theme palette (--v-* first) instead of falling back
# to literal light colours, which were unreadable on the dark Vantage theme.
# r3: drop the Tools -> IPv6 page. It called luci.vantage ipv6_mode, which no
# rpcd provider implements, and /usr/sbin/aw1000-ipv6-mode is not in the image,
# so the button could never work. IPv6 is not used on this build.
# r4: the page gets them back, backed by the `byte` rpcd object instead:
# one-click AdGuard Home password change (agh-passwd + `agh_password`) and a
# working Tools -> IPv6 switch (`ipv6_mode`, PDP type + RA/DHCPv6 + AAAA).
# r5: Status -> Overview -> System is rewritten at first boot: Architecture,
# Target Platform and Load Average gone, Firmware Version short ("BYTE v1.1.3")
# instead of "BYTE 1.1.3 r0-xxxxxxx / LuCI ...". luci-mod-status owns that
# include file, so it is patched from uci-defaults, not shipped in ./root.
# r9 (1.1.9): Tools -> IPv6 gets a DNS bypass guard switch: blocks LAN DoT (853)
# and QUIC (UDP 443) so Private DNS/QUIC resolvers must fall back to the router
# or lose resolution. Stored in /etc/config/byte, applied by byte-dns-guard, and
# exposed through the byte rpcd object (dns_guard status|on|off).
# r8 (1.1.9): two regressions from the 32f101a re-vendor are fixed. network.lan.
# ipaddr is a CIDR, and AdGuardHome's bind_hosts/http.address reject the prefix,
# so lan_ipv4() strips it again. The first-run admin API binds the DNS address it
# is handed; it ran while dnsmasq still owned :53, answered HTTP 400, and left
# users: [] (no admin). It now probes on a scratch loopback DNS port and only the
# users: block is transplanted.
# r7 (1.1.5): the vendored installer is the current openwrt-agh-passwall2
# (32f101a): AdGuard Home resolves over DoH (Quad9 + Cloudflare), dnsmasq moves
# to 5335 for .lan, and an nft chain at priority -150 forces every other
# plaintext DNS query back to :53 before PassWall2's NAT. This is the chain the
# reference router has been running, not the old :53/:54/fallback one.
# r6: DNS resilience. The vendored installer derives AdGuardHome's fallback_dns
# from the current WAN lease instead of shipping an empty list, sets
# upstream_timeout, asserts that dnsmasq never shares :53 with AdGuardHome and
# probes an uncached name at install time. The watchdog now probes resolution
# and walks a repair ladder that always ends with dnsmasq back on :53, and it is
# scheduled by the packaged 60s procd guard (/etc/init.d/agh-pw-guard) because
# the panel starts the installer with --no-watchdog, so 1.1.3 had no watchdog at
# all. WAN-up hotplug refreshes the fallback list; the panel shows resolver
# health and a rescue notice.
PKG_RELEASE:=9

PKG_MAINTAINER:=Ace1337z
PKG_LICENSE:=GPL-3.0-only

LUCI_TITLE:=BYTE - AdGuard Home + PassWall2 one-page panel
LUCI_DESCRIPTION:=Single LuCI page under Tools to install, wire, inspect and undo the AdGuard Home + PassWall2 DNS chain. Ships the vendored upstream installer (IPv4-only bind, first-run web admin through the AdGuard API), so no runtime network fetch.
# luci-base: JS framework + resource loading. rpcd: the ubus exec plugin host.
# libubox/jsonfilter: jshn.sh + jsonfilter used by the backend script.
# agh-passwd: bcrypt helper for the one-click web admin password change
# (`agh_password`); AdGuard Home itself has no API for it after first run.
LUCI_DEPENDS:=+luci-base +rpcd +libubox +jsonfilter +ubus +agh-passwd

# luci.mk installs ./htdocs -> /www and ./root -> / automatically, so the
# menu json, rpcd acl, backend script, uci-defaults and the vendored installer
# all land in the right place without a custom Package/install block.
include $(TOPDIR)/feeds/luci/luci.mk

$(eval $(call BuildPackage,luci-app-byte))