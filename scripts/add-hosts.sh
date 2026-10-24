#!/bin/sh
grep -q steamloopback.host /etc/hosts || echo "127.0.0.1 steamloopback.host" >> /etc/hosts
cat /etc/hosts
