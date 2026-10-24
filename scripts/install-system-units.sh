#!/bin/sh
set -e
mkdir -p /usr/lib/systemd/system/multi-user.target.wants
for u in plugin_loader input-nodes; do
  cp -f "/etc/systemd/system/$u.service" "/usr/lib/systemd/system/$u.service"
  ln -sf "/usr/lib/systemd/system/$u.service" "/usr/lib/systemd/system/multi-user.target.wants/$u.service"
done
ls -l /usr/lib/systemd/system/multi-user.target.wants/plugin_loader.service /usr/lib/systemd/system/multi-user.target.wants/input-nodes.service
