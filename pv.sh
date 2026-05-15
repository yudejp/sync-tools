#!/bin/sh

set -eu

# Example:
#   IGNORE_PVC_PATTERNS='cache-* tmp-data' sh pv.sh
# Requires at least one running pod that already mounts each target PVC.

DEST_HOST=${DEST_HOST:-root@ttj1pve1.tun.y2e.org}
DEST_BASE_DIR=${DEST_BASE_DIR:-/mnt/store1/pv}
IGNORE_PVC_PATTERNS=${IGNORE_PVC_PATTERNS:-}
IGNORE_PVC_PATTERNS='pgdata-za-pg-16-* redis-redis-* open-webui-data pgadmin-data-pgadmin-* valkey-data-vk2-*'
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TAB=$(printf '\t')

CLAIM_INDEX_FILE=$(mktemp)
PVC_LIST_FILE=$(mktemp)

cleanup() {
	rm -f "$CLAIM_INDEX_FILE" "$PVC_LIST_FILE"
}

trap cleanup EXIT HUP INT TERM

log() {
	printf '%s\n' "$*" >&2
}

quote_sh() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\''/g")"
}

normalize_storageclass() {
	case ${1:-} in
		''|'<none>')
			printf '%s\n' 'no-storageclass'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

should_ignore_pvc() {
	pvc_name=$1

	for pattern in $IGNORE_PVC_PATTERNS; do
		case "$pvc_name" in
			$pattern)
				return 0
				;;
		esac
	done

	return 1
}

build_claim_index() {
	volumes_file=$(mktemp)
	mounts_file=$(mktemp)

	kubectl get pods -A -o go-template='{{range .items}}{{if eq .status.phase "Running"}}{{ $ns := .metadata.namespace }}{{ $pod := .metadata.name }}{{range .spec.volumes}}{{if .persistentVolumeClaim}}{{printf "V\t%s\t%s\t%s\t%s\n" $ns $pod .name .persistentVolumeClaim.claimName}}{{end}}{{end}}{{end}}{{end}}' > "$volumes_file"
	kubectl get pods -A -o go-template='{{range .items}}{{if eq .status.phase "Running"}}{{ $ns := .metadata.namespace }}{{ $pod := .metadata.name }}{{range .spec.containers}}{{ $container := .name }}{{range .volumeMounts}}{{printf "M\t%s\t%s\t%s\t%s\t%s\n" $ns $pod $container .name .mountPath}}{{end}}{{end}}{{end}}{{end}}' > "$mounts_file"

	awk -F '\t' '
		NR == FNR {
			if ($1 == "V") {
				claim_by_volume[$2 SUBSEP $3 SUBSEP $4] = $5
			}
			next
		}
		$1 == "M" {
			volume_key = $2 SUBSEP $3 SUBSEP $5
			if (!(volume_key in claim_by_volume)) {
				next
			}

			claim_key = $2 SUBSEP claim_by_volume[volume_key]
			if (claim_key in emitted) {
				next
			}

			print $2 "\t" claim_by_volume[volume_key] "\t" $3 "\t" $4 "\t" $6
			emitted[claim_key] = 1
		}
	' "$volumes_file" "$mounts_file" > "$CLAIM_INDEX_FILE"

	rm -f "$volumes_file" "$mounts_file"
}

find_live_mount_for_claim() {
	namespace=$1
	claim_name=$2

	awk -F '\t' -v claim_namespace="$namespace" -v claim_name="$claim_name" '
		$1 == claim_namespace && $2 == claim_name {
			print $3 "\t" $4 "\t" $5
			exit
		}
	' "$CLAIM_INDEX_FILE"
}

stream_to_remote_dir() {
	pv_name=$1
	pvc_name=$2
	namespace=$3
	storageclass=$4
	archive_name=$pv_name-$pvc_name-$storageclass-$TIMESTAMP.tar.zst
	remote_script='
set -eu
dest_base_dir=$1
archive_name=$2
pv_name=$3
pvc_name=$4
pvc_namespace=$5
storageclass=$6

mkdir -p "$dest_base_dir"

final_path=$dest_base_dir/$archive_name
tmp_path=$(mktemp "$dest_base_dir/.incoming.$archive_name.XXXXXX")

cleanup_tmp() {
	rm -f "$tmp_path"
}

trap cleanup_tmp EXIT HUP INT TERM

cat > "$tmp_path"

rm -f "$final_path"
mv "$tmp_path" "$final_path"

trap - EXIT HUP INT TERM
'

	ssh "$DEST_HOST" "sh -c $(quote_sh "$remote_script") sh $(quote_sh "$DEST_BASE_DIR") $(quote_sh "$archive_name") $(quote_sh "$pv_name") $(quote_sh "$pvc_name") $(quote_sh "$namespace") $(quote_sh "$storageclass")"
}

backup_from_running_pod() {
	namespace=$1
	pvc_name=$2
	pv_name=$3
	storageclass=$4
	mount_info=$(find_live_mount_for_claim "$namespace" "$pvc_name")

	if [ -z "$mount_info" ]; then
		log "no running pod mounts pvc=$pvc_name in namespace=$namespace"
		return 1
	fi

	IFS=$TAB read -r pod_name container_name mount_path <<EOF
$mount_info
EOF

	log "backing up pvc=$pvc_name from running pod=$pod_name container=$container_name"
	kubectl exec -n "$namespace" -c "$container_name" "$pod_name" -- tar cf - -C "$mount_path" . \
		| zstd -19 -T0 \
		| stream_to_remote_dir "$pv_name" "$pvc_name" "$namespace" "$storageclass"
}

build_claim_index
kubectl get pvc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.spec.volumeName}{"|"}{.spec.storageClassName}{"|"}{.status.phase}{"\n"}{end}' > "$PVC_LIST_FILE"
ssh "$DEST_HOST" "mkdir -p $(quote_sh "$DEST_BASE_DIR")"

while IFS='|' read -r namespace pvc_name pv_name storageclass status; do
	[ -n "${namespace:-}" ] || continue

	if [ "$status" != 'Bound' ] || [ -z "$pv_name" ] || [ "$pv_name" = '<none>' ]; then
		continue
	fi

	if should_ignore_pvc "$pvc_name"; then
		log "skipping pvc=$pvc_name because it matches IGNORE_PVC_PATTERNS"
		continue
	fi

	storageclass=$(normalize_storageclass "$storageclass")
	backup_from_running_pod "$namespace" "$pvc_name" "$pv_name" "$storageclass"
done < "$PVC_LIST_FILE"
