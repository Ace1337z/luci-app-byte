# luci-app-byte

BYTE — a single LuCI page that installs, wires, inspects and **undoes** the
AdGuard Home + PassWall2 DNS chain on OpenWrt. The successor to the in-firmware
panel, usable on any OpenWrt device (LuCI + rpcd).

```
LAN clients → router :53 → AdGuard Home → PassWall2 DNS (127.0.0.1:15353)
                                        └→ dnsmasq :54 (.lan / .local names)
```

- **Menu**: Tools → BYTE (AdGuard Home + PassWall2)
- **Packages**: `luci-app-byte_1.0.0-1_all.ipk` (opkg) and
  `luci-app-byte-1.0.0-r1.apk` (apk)
- **No runtime network fetch**: the upstream installer is vendored and pinned
  (see `VENDORED_PIN=` header in the script) so an upstream change can never
  silently alter the behaviour of the panel.
- **Dry run / undo**: the new upstream installer ships `--dry-run`,
  `--uninstall` and `--purge`; the panel exposes all of them with live
  streaming output.

## What it does

| Action | What happens |
| --- | --- |
| Install and wire | Installs AdGuardHome (+ LuCI app) if missing, moves dnsmasq to :54, points AdGuard at PassWall2 DNS `tcp://127.0.0.1:15353`, keeps `.lan`/`.local`/`.home.arpa` on dnsmasq, disables SafeSearch, installs a 2-minute health watchdog |
| Dry run first | Runs the same installer with `--dry-run` — shows what would change, changes nothing |
| Undo wiring | `--uninstall`: dnsmasq back to :53, firewall rules removed, config kept |
| Purge (with undo) | Also deletes the AdGuardHome install (service, binary, config) |
| Start/Stop/Restart | Controls the AdGuardHome service |
| Autostart on/off | Toggles service autostart |
| Setup log | Live tail of the current/last installer run with exit status |

The panel also shows the live state (AdGuard Home version/running, DNS chain,
PassWall2 node count and service state, WAN IP, load, memory) and links out to
AdGuard Home's web UI and the PassWall2 page. PassWall2 **nodes are never
auto-added** — that is always done by you in PassWall2.

## Requirements

- OpenWrt with LuCI (luci-base), rpcd, libubox, jsonfilter, ubus
- A working opkg or apk package manager

## Install

### opkg (ipk)

```sh
opkg update
opkg install luci-app-byte_1.0.0-1_all.ipk
```

### apk

```sh
apk add --allow-untrusted ./luci-app-byte-1.0.0-r1.apk
```

The post-install script clears the LuCI caches and reloads rpcd so the page
appears immediately.

## Building

Requires only POSIX sh, `tar`, `gzip`, `ar`, `curl` and `openssl` — **no
OpenWrt SDK needed**. A static `apk-tools` 3.x is fetched once into `.tools/`
for the apk build.

```sh
./build.sh            # both formats
./build.sh ipk        # ipk only
./build.sh apk        # apk only
```

Artifacts land in `dist/`.

### CI

GitHub Actions builds both packages on every push/PR and uploads them as
artifacts. Pushing a `v*` tag also creates a GitHub Release with both files.

## Development layout

```
htdocs/luci-static/resources/byte/byte.css    scoped CSS (everything .byte-*)
htdocs/luci-static/resources/view/byte/overview.js   LuCI JS view
root/usr/libexec/rpcd/byte                    rpcd backend (status/setup/action/log)
root/usr/libexec/luci-app-byte/agh-passwall2.sh  vendored, pinned upstream installer
root/usr/share/luci/menu.d/luci-app-byte.json menu (Tools → BYTE)
root/usr/share/rpcd/acl.d/luci-app-byte.json  rpcd ACL (read + write verbs)
root/etc/uci-defaults/90-luci-app-byte        rpcd restart once after install
Makefile                                      OpenWrt luci.mk package definition
build.sh                                      offline dual-format builder
```

## License

GPL-3.0-only. The vendored `agh-passwall2.sh` is distributed under the terms
of its upstream repository ([Ace1337z/openwrt-agh-passwall2](https://github.com/Ace1337z/openwrt-agh-passwall2)).
