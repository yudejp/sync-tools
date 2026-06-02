#!/bin/sh

rsync -avz --partial --delete /mnt/store1/archives/family/ root@hnd1pve1.tail5b1c5.ts.net:/mnt/store1/family/
rsync -avz --partial --delete /mnt/store3/music/ root@hnd1pve1.tail5b1c5.ts.net:/mnt/store1/music/
rsync -avz --partial --delete /mnt/store3/docs/ root@hnd1pve1.tail5b1c5.ts.net:/mnt/store1/docs/
rsync -avz --partial --delete /mnt/store3/paperless/ root@hnd1pve1.tail5b1c5.ts.net:/mnt/store1/paperless/
rsync -avz --partial --delete /mnt/store3/video/ root@hnd1pve1.tail5b1c5.ts.net:/mnt/store1/video/
rsync -avz --partial --delete /mnt/store3/images/ root@hnd1pve1.tail5b1c5.ts.net:/mnt/store1/images/
rsync -avz --partial --delete /mnt/store3/software/ root@hnd1pve1.tail5b1c5.ts.net:/mnt/store1/software/
rsync -avz --partial --exclude 'immich/backups' --exclude 'immich/encoded-video' --exclude 'immich/profile' --exclude 'immich/thumbs' --exclude 'upload' --delete /mnt/store3/photo/ root@hnd1pve1.tail5b1c5.ts.net:/mnt/store1/photo/
