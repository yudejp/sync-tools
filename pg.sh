#!/bin/sh

set -eu

DEFAULT_REQUIRED_BYTES=$((10 * 1024 * 1024 * 1024))
TIMESTAMP=$(date +%F-%T)

ensure_remote_space() {
	host=$1
	target_dir=$2

	ssh "$host" "TARGET_DIR='$target_dir' DEFAULT_REQUIRED_BYTES='$DEFAULT_REQUIRED_BYTES' sh -s" <<'EOF'
set -eu

target_dir=$TARGET_DIR
default_required_bytes=$DEFAULT_REQUIRED_BYTES

available_bytes=$(df -Pk "$target_dir" | awk 'NR==2 { print $4 * 1024 }')
latest_size=0

for file in "$target_dir"/*.sql.zst; do
	[ -e "$file" ] || continue
	latest_size=$(stat -c %s "$file")
done

required_bytes=$default_required_bytes
if [ "$latest_size" -gt 0 ]; then
	required_bytes=$((latest_size + latest_size / 5 + 1024 * 1024 * 1024))
	if [ "$required_bytes" -lt "$default_required_bytes" ]; then
		required_bytes=$default_required_bytes
	fi
fi

if [ "$available_bytes" -lt "$required_bytes" ]; then
	echo "insufficient free space in $target_dir: available=${available_bytes}B required=${required_bytes}B" >&2
	exit 1
fi
EOF
}

backup_to() {
	host=$1
	target_dir=$2
	target_file="$target_dir/$TIMESTAMP.sql.zst"

	ensure_remote_space "$host" "$target_dir"
	kubectl exec --stdin za-pg-16-0 -- pg_dumpall -U postgres | zstd -19 -T0 | ssh "$host" "cat > '$target_file'"
}

backup_to root@ttj1sh1.tun.y2e.org /mnt/prod/pg
backup_to root@hnd1pve1.tun.y2e.org /mnt/store1/pg
