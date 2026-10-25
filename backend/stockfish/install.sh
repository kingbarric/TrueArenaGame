#!/bin/sh
# Image build only. Official, immutable release archives include their GPL
# licence and complete engine source, retained beside the executable.
set -eu
destination="${1:?destination required}"
case "$(uname -m)" in
  x86_64)
    platform=linux-x86-64
    checksum=9defc0d4e55d49c65a6d042f3e571a39fcea499ade6dbe741b53b8c65e03611f
    ;;
  aarch64|arm64)
    platform=linux-arm64
    checksum=fe26cfd1d9db4c8af3d21e24d9ff34cacb31c1f940085a7583da11796f2bac01
    ;;
  *) echo 'Unsupported Stockfish image architecture' >&2; exit 1 ;;
esac
archive=$(mktemp)
trap 'rm -f "$archive"' EXIT
url="https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-$platform-universal.tar.gz"
curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 "$url" -o "$archive"
printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c -
mkdir -p "$destination"
tar -xzf "$archive" --strip-components=1 -C "$destination"
test -s "$destination/Copying.txt"
test -d "$destination/src"
chmod 755 "$destination/stockfish-$platform-universal"
ln -s "stockfish-$platform-universal" "$destination/stockfish"
printf 'Stockfish 19, unmodified official binary\nArchive: %s\nSHA256: %s\nSource: https://github.com/official-stockfish/Stockfish/tree/sf_19\n' \
  "$url" "$checksum" > "$destination/SOURCE.txt"
printf 'uci\nquit\n' | "$destination/stockfish" > /tmp/stockfish-build-check.txt
grep -q '^uciok' /tmp/stockfish-build-check.txt
rm -f /tmp/stockfish-build-check.txt
