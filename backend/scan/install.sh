#!/bin/sh
# Image-build only: pinned official Scan 3.1 source and data, built for the target CPU.
set -eu
destination="${1:?destination required}"
archive=$(mktemp)
trap 'rm -f "$archive"' EXIT
url=https://hjetten.home.xs4all.nl/scan/scan_31.zip
checksum=7579cc16cb3650a6bc5e98035a4052fe7941959050f72e4c4b42fc6fde02ece4
curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 "$url" -o "$archive"
printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c -
temporary=$(mktemp -d)
unzip -q "$archive" -d "$temporary"
mkdir -p "$destination"
cp -R "$temporary/scan_31/." "$destination/"
rm -rf "$temporary"
# No x86-only -mpopcnt or -march=native: the same build works on ARM64 and x86-64.
make -C "$destination/src" -j2 CXX=g++ \
  'CXXFLAGS=-pthread -std=c++14 -fno-rtti -O3 -DNDEBUG' 'LDFLAGS=-pthread -O3'
cp "$destination/src/scan" "$destination/scan"
make -C "$destination/src" clean
rm -f "$destination/scan.exe" "$destination/scan_mac" "$destination/scan_linux"
chmod 755 "$destination/scan"
test -s "$destination/license.txt"
test -s "$destination/data/eval"
printf 'Scan 3.1, unmodified official source, portable C++14 build\nArchive: %s\nSHA256: %s\n' \
  "$url" "$checksum" > "$destination/SOURCE.txt"
cp "$0" "$destination/build-release.sh"
# The ZIP preserves owner-only data/config permissions; the runtime uses an unprivileged user.
chmod -R a+rX "$destination"
(cd "$destination" && printf 'hub\nquit\n' | ./scan hub) > /tmp/scan-build-check.txt
grep -q '^wait' /tmp/scan-build-check.txt
rm -f /tmp/scan-build-check.txt
