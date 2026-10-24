#!/bin/sh
# Mask phone-specific units that cannot work inside the DroidSpaces container.
# Units live in /usr/lib because the /etc overlay is not visible to systemd's
# first unit scan at boot.
set -u
cd /usr/lib/systemd/system || exit 1

for u in qteesupplicant.service sheng-devauth.service xiaomi-sheng-thp.service bluetooth.service; do
  if [ -L "$u" ]; then
    echo "already symlink: $u"
    continue
  fi
  if [ -f "$u" ]; then
    [ -f "$u.droidspaces-backup" ] || cp -a "$u" "$u.droidspaces-backup"
    ln -sf /dev/null "$u"
    echo "masked: $u"
  else
    echo "missing: $u"
  fi
done

systemctl daemon-reload
systemctl stop xiaomi-sheng-thp.service sheng-devauth.service qteesupplicant.service bluetooth.service 2>/dev/null
systemctl reset-failed 2>/dev/null

echo "--- state ---"
ls -l qteesupplicant.service sheng-devauth.service xiaomi-sheng-thp.service bluetooth.service
