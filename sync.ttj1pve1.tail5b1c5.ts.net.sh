#!/bin/sh

rsync -avz --partial --delete /mnt/store4/dtv/ root@ttj1pve1.tun.y2e.org:/mnt/store2/dtv/
rsync -avz --delete --partial \
	--exclude '.git' \
	--exclude 'dtv-tuner/config/metadata' \
	--exclude 'dtv-tuner/epgstation/logs' \
	--exclude 'dtv-tuner/konomitv/data/thumbnails' \
	--exclude 'immich/postgres' \
    --exclude 'jellyfin/config/metadata' \
    --exclude 'navidrome/data' \
    --exclude 'paperless/data' \
    --exclude 'scanopy/db' \
    --exclude 'scanopy/data' \
	--delete \
	/mnt/prod/docker/ \
	root@ttj1pve1.tun.y2e.org:/mnt/store1/docker.nrt1sh1/
