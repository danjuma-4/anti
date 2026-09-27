# Redroid 11 with Google Play Services

## What this is

A Docker image of Android 11 that has **real Google Play Services** installed
into its system partition. It is committed as a single tag
(`redroid/redroid:11.0.0-gapps`), so Play Services is present on every
container boot. No startup script, no side-loading loop, no `entrypoint`
override.

That last point is the one that matters. `Settings > Accounts > Add account`
builds its list by asking `AccountManager` which authenticator APKs are
installed. Google Play Services is the APK that registers the `com.google`
authenticator. With the stock `redroid/redroid:11.0.0-latest` image that APK
does not exist, so the list has no Google row and no network setting can
change that.

## What you copy where

| File | Runs on | When |
|---|---|---|
| `01-build-and-boot.sh` | VPS, as root | once |
| `docker-compose.yml` | VPS | instead of the script's `docker run`, optional |
| `02-proxy.sh` | VPS | optional, after it is verified working |
| `connect.ps1` | your Windows PC | each time you want the screen |

Transfer them, e.g.:

```bash
scp -r ./redroid-gapps root@YOUR.VPS.IP.HERE:~/
```

## One-time setup

On Windows, so the script knows where your VPS is:

```powershell
copy config.local.ps1.example config.local.ps1
notepad config.local.ps1
```

`config.local.ps1` is gitignored, so your server address stays out of the
repository. On the VPS there is nothing to configure.

## Run order

**1. Build.** On the VPS:

```bash
cd ~/redroid-gapps
bash 01-build-and-boot.sh
```

Expect 5-15 minutes. It clones `ayasa520/redroid-script`, which injects
OpenGApps into the system partition and commits the image, then boots the
container and verifies `com.google.android.gms` resolves.

**2. Connect.** On Windows:

```powershell
powershell -ExecutionPolicy Bypass -File connect.ps1
```

The scrcpy window opens. Swipe up, then `Settings > Accounts > Add account >
Google`.

**3. Optional, Play Protect certification.** An uncertified device blocks some
Play features but not the Add Account screen, so this is not required to sign
in.

```bash
adb connect 127.0.0.1:5555
adb root
adb shell 'sqlite3 /data/data/com.google.android.gsf/databases/gservices.db \
  "select * from main where name = \"android_id\";"'
```

Register that id at https://www.google.com/android/uncertified, wait ~15 min,
then clear Play Store and Play Services app data.

## Managing it after the first boot

Either keep using the script's container:

```bash
docker restart redroid_google_instance
```

or switch to compose, which points at the same image and the same `./data`:

```bash
cd ~/redroid-gapps
docker rm -f redroid_google_instance
docker compose up -d
```

## Proxy, if you want it

Only after the container is confirmed working. Setting it inside Android is
what leaves the published adb port alone; a sibling proxy container puts that
port behind another netns, which is what caused the intermittent
"actively refused" in earlier attempts.

```bash
bash 02-proxy.sh set proxy.example.com 8080
bash 02-proxy.sh show
bash 02-proxy.sh off          # undo
```
The exclude list this writes is what keeps the device's own loopback and adb
bridge traffic out of the proxy. Without it Android routes its internal
traffic through the proxy, adbd loses its socket, and you get "device
offline" plus a black window.

Verify from the device browser: `https://ipinfo.io`, `https://whoer.net`.

## What is deliberately not here

- **No fingerprint spoofing.** No randomized IMEI, serial, MAC, or android-id,
  and no `ro.build.fingerprint` rewriting to present the container as a
  Samsung device. Spoofing a hardware identity to defeat Google's
  phone-verification check on account creation is not something I'll help
  build.
- **No `http_proxy` in compose `environment:`.** Android does not read it
  there. It has been dropped because it did nothing except confuse the
  debugging.
- **No `iptables -F`.** The build script only deletes the specific stray
  `--dport 5555` INPUT rules. A blanket flush wipes Docker's NAT table and
  silently breaks every published port on the host.

## If something fails

```bash
docker ps -a                                    # Up / restarting / exited?
ss -tlnp | grep 5555                            # anything listening?
docker logs --tail 50 redroid_google_instance
docker exec redroid_google_instance getprop ro.build.version.release
```

If the container is restarting, delete `./data` and start over, or just re-run
`01-build-and-boot.sh` - it resets the data partition on every run.

If the pull or clone fails, it is a network or disk problem on the VPS, not
these files. Check `df -h /` and `docker images`.
