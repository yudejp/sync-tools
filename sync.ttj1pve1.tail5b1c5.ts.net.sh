#!/bin/sh

rsync -avz --partial --delete /mnt/store4/dtv/ root@ttj1pve1.tun.y2e.org:/mnt/store2/dtv/
rsync -avz --partial --exclude '.git' --delete /mnt/prod/docker/ root@ttj1pve1.tun.y2e.org:/mnt/store1/docker.nrt1sh1/
