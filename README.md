# luci-app-byte

BYTE — a single LuCI page that installs, wires, inspects and **undoes** the
AdGuard Home + PassWall2 DNS chain on OpenWrt. The successor to the in-firmware
panel, usable on any OpenWrt device (LuCI + rpcd).

```
LAN clients → router :53 → AdGuard Home → dnsmasq :54 → PassWall2 DNS
                                        └→ .lan / .local / .home.arpa
```

- **Menu**: Tools → BYTE (AdGuard Home + PassWall2)
- **Feed packages, no vendor tarball**: the vendored installer installs
  `adguardhome` and `luci-app-adguardhome` through the device package manager
  (opkg/apk), so the binary and init script stay feed-managed. A reachable
  package feed is required at install time.
- **No runtime network fetch of the script**: the upstream installer is
  vendored and pinned (see `VENDORED_PIN=` header in the script), so an
  upstream change can never silently alter the behaviour of the panel.
- **Site policy**: the panel always runs the installer with `IPV6_ENABLE=0`
  and `--no-watchdog` (no 2-minute health cron). Active listeners are then IPv4
  only: DNS on the LAN IPv4 plus `127.0.0.1`, web UI on `<lan-ip>:3000` - a
  plain `0.0.0.0` makes AdGuardHome open a dual-stack `[::]` socket.
- **Web admin**: the install dialog takes a user name and password; both are
  handed to the installer, which creates the account through AdGuardHome's own
  first-run `/control/install/configure` API. A blank password is generated
  (16 characters) and written to `/etc/agh-pw-backup/agh-admin.txt` (0600),
  and the credentials also appear in the setup log.
- **Dry run / undo**: `--dry-run` and `--uninstall` are always exposed.
  `--purge` is passed only when the vendored installer supports it; the
  feed-based installer lineage does not, so Purge degrades to plain uninstall.

## What it does

| Action | What happens |
| --- | --- |
| Install and wire | Installs `adguardhome` + `luci-app-adguardhome` from the configured feed if missing, moves dnsmasq to :54, points AdGuard at dnsmasq (:54) which forwards to PassWall2 DNS, keeps `.lan`/`.local`/`.home.arpa` local, disables SafeSearch, creates the web admin through the first-run API. IPv4-only DNS and web listeners, no watchdog cron |
| Dry run first | Runs the same installer with `--dry-run` — shows what would change, changes nothing |
| Undo wiring | `--uninstall`: dnsmasq back to :53, firewall rules removed, config kept |
| Purge (with undo) | Passed only if the vendored installer supports `--purge` (feed-based lineage does not; Purge then equals Undo) |
| Start/Stop/Restart | Controls the AdGuardHome service |
| Autostart on/off | Toggles service autostart |
| Setup log | Live tail of the current/last installer run with exit status |

The panel also shows the live state (AdGuard Home version/running, DNS chain,
PassWall2 node count and service state, WAN IP, load, memory) and links out to
AdGuard Home's web UI and the PassWall2 page. PassWall2 **nodes are never
auto-added** — that is always done by you in PassWall2.

## Requirements

- OpenWrt with LuCI (luci-base), rpcd, libubox, jsonfilter, ubus
- A working opkg or apk package manager with a reachable feed that carries
  `adguardhome` (and ideally `luci-app-adguardhome`) — the installer pulls the
  daemon from that feed, it does not download a vendor tarball
- PassWall2 installed and running
- A `curl` or feature-compatible `wget` on the device for the first-run admin
  call (both are present on stock OpenWrt images)

## Install into a firmware build

Put this directory in a package feed, e.g. `package/luci-app-byte`, then
select `luci-app-byte` in `make menuconfig` (LuCI → Applications) and build:

```sh
git clone https://github.com/Ace1337z/luci-app-byte.git package/luci-app-byte
make menuconfig   # LuCI → Applications → luci-app-byte
make -j$(nproc)
```

With the SDK, the same package can be built straight from this tree:

```sh
make package/luci-app-byte/compile V=s
```

The resulting ipk/apk is the firmware's normal package output; no separate
builder or CI is required.

The post-install script clears the LuCI caches and reloads rpcd so the page
appears immediately.

## Development layout

```
Makefile                                          OpenWrt luci.mk package definition
htdocs/luci-static/resources/byte/byte.css        scoped CSS (everything .byte-*)
htdocs/luci-static/resources/view/byte/overview.js LuCI JS view
root/etc/uci-defaults/90-luci-app-byte            rpcd restart once after install
root/usr/libexec/luci-app-byte/agh-passwall2.sh   vendored, pinned upstream installer
root/usr/libexec/rpcd/byte                        rpcd backend (status/setup/action/log)
root/usr/share/luci/menu.d/luci-app-byte.json     menu (Tools → BYTE)
root/usr/share/rpcd/acl.d/luci-app-byte.json      rpcd ACL (read + write verbs)
```

`luci.mk` installs `./htdocs` → `/www` and `./root` → `/`, so no custom
`Package/install` block is required.

## Troubleshooting
`apk add` failing with `unable to select packages: luci-app-byte (no such
package): required by: world[luci-app-byte]` means the package was once added
to `/etc/apk/world` by hand. No feed provides it, so every `apk` transaction
aborts until that line is removed:
```sh
grep -v '^luci-app-byte$' /etc/apk/world > /tmp/world && mv /tmp/world /etc/apk/world
```
The panel does not need the package manager entry: it only ships files.

### Web UI is not on 127.0.0.1
With IPv6 disabled the UI listens on `<lan-ip>:3000` only. A local `curl` from
the router must use the LAN address (`http://192.168.1.1:3000/control/status`),
not `127.0.0.1`, or it will be refused.

## License

GPL-3.0-only. The vendored `agh-passwall2.sh` is distributed under the terms
of its upstream repository ([Ace1337z/openwrt-agh-passwall2](https://github.com/Ace1337z/openwrt-agh-passwall2)).
