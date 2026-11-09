#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
zig build -Drelease --prefix /usr/local
install -m 0755 raspberry_pi/temper.service.sh /etc/init.d/temper
rc-update add temper default
rc-service temper restart
