#!/system/bin/sh
MODDIR=${0%/*}
chcon u:object_r:vendor_configs_file:s0 "$MODDIR/excluded-input-devices.xml" 2>/dev/null
mount --bind "$MODDIR/excluded-input-devices.xml" /vendor/etc/excluded-input-devices.xml
