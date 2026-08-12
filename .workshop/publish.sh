#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
CONFIG="$SCRIPT_DIR/config"
TEMPLATE="$SCRIPT_DIR/item.vdf.template"

CHANGE_NOTE=""
CHANGE_NOTE_SET=false
DRY_RUN=false
ASSUME_YES=false
WORK_DIR=""

usage() {
    cat <<'EOF'
Usage:
  .workshop/publish.sh [--changenote NOTE] [--dry-run] [--yes]

By default, the update note is built from the version and current English
changelog entry in modinfo.lua.

Required environment variables:
  STEAMCMD    Absolute path to the official steamcmd.sh
  STEAM_USER  Steam account name that owns the Workshop item

Options:
  --changenote NOTE  Override the update note; NOTE may contain newlines
  --dry-run          Build and inspect the payload without invoking SteamCMD
  --yes              Skip the interactive Workshop ID confirmation
  -h, --help         Show this help

Examples:
  .workshop/publish.sh --dry-run
  .workshop/publish.sh --changenote $'Version: X.Y.Z\n\nChanges:\n- Update note.' --dry-run
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}

vdf_escape() {
    local escaped="${1//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf -v "$2" '%s' "$escaped"
}

extract_current_changelog() {
    perl -0777 -e '
        $_ = <>;
        my @matches = /changelog\s*=\s*zheng\s*\(\s*\[\[(.*?)\]\]\s*,\s*\[\[(.*?)\]\]\s*\)/sg;
        exit 1 unless @matches == 2;

        my $changelog = $matches[1];
        $changelog =~ s/\A(?:[\t ]*\n)+//;
        $changelog =~ s/(?:\n[\t ]*)+\z//;
        $changelog =~ s/\n[\t ]*Recent Changes:[\t ]*(?:\n|\z).*//s;
        $changelog =~ s/(?:\n[\t ]*)+\z//;
        exit 1 unless $changelog =~ /\S/;

        print $changelog;
    ' "$1"
}

while (($# > 0)); do
    case "$1" in
        --changenote)
            (($# >= 2)) || die "--changenote requires a value"
            CHANGE_NOTE="$2"
            CHANGE_NOTE_SET=true
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes)
            ASSUME_YES=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[[ -n "${STEAMCMD:-}" ]] || die "STEAMCMD is empty; set it to the official steamcmd.sh path"
[[ -n "${STEAM_USER:-}" ]] || die "STEAM_USER is empty; set it to the Workshop owner account"
[[ -x "$STEAMCMD" ]] || die "STEAMCMD is not executable: $STEAMCMD"
[[ -f "$CONFIG" ]] || die "Workshop config not found: $CONFIG"
[[ -f "$TEMPLATE" ]] || die "VDF template not found: $TEMPLATE"

APP_ID="$(sed -n 's/^APP_ID=//p' "$CONFIG")"
PUBLISHED_FILE_ID="$(sed -n 's/^PUBLISHED_FILE_ID=//p' "$CONFIG")"
[[ "$APP_ID" =~ ^[1-9][0-9]*$ ]] || die "APP_ID must be a non-zero numeric ID"
[[ "$PUBLISHED_FILE_ID" =~ ^[1-9][0-9]*$ ]] || die "PUBLISHED_FILE_ID must be a non-zero numeric ID"
readonly APP_ID PUBLISHED_FILE_ID

[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || die "working tree is not clean"

for required_path in modinfo.lua modmain.lua modclientmain.lua; do
    git -C "$REPO_ROOT" cat-file -e "HEAD:$required_path" 2>/dev/null || \
        die "required Workshop file is missing from HEAD: $required_path"
done

CONTENT_PATHS=()
while IFS= read -r -d '' entry; do
    metadata="${entry%%$'\t'*}"
    content_path="${entry#*$'\t'}"
    object_type="${metadata#* }"
    object_type="${object_type%% *}"

    [[ "$content_path" == .* ]] && continue
    if [[ "$object_type" == tree || "$content_path" == *.lua ]]; then
        CONTENT_PATHS+=("$content_path")
    fi
done < <(git -C "$REPO_ROOT" ls-tree -z HEAD)

((${#CONTENT_PATHS[@]} > 0)) || die "HEAD contains no publishable top-level directories or Lua files"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/glassicapi-workshop.XXXXXX")"
trap cleanup EXIT HUP INT TERM
readonly CONTENT_DIR="$WORK_DIR/content"
readonly VDF_FILE="$WORK_DIR/item.vdf"
mkdir -p "$CONTENT_DIR"

git -C "$REPO_ROOT" archive --format=tar HEAD -- "${CONTENT_PATHS[@]}" | tar -xf - -C "$CONTENT_DIR"

VERSION="$(awk -F'"' '/^[[:space:]]*version[[:space:]]*=[[:space:]]*"/ { print $2; exit }' "$CONTENT_DIR/modinfo.lua")"
[[ -n "$VERSION" ]] || die "could not read version from modinfo.lua"

if [[ "$CHANGE_NOTE_SET" == true ]]; then
    CHANGE_NOTE="${CHANGE_NOTE//$'\r\n'/$'\n'}"
    [[ "$CHANGE_NOTE" != *$'\r'* ]] || die "--changenote contains an unsupported carriage return"
    [[ "$CHANGE_NOTE" =~ [^[:space:]] ]] || die "--changenote must not be empty"
else
    CURRENT_CHANGELOG="$(extract_current_changelog "$CONTENT_DIR/modinfo.lua")" || \
        die "could not read the current English changelog from modinfo.lua"
    CHANGE_NOTE="$(printf 'Version: %s\n\nChanges:\n%s' "$VERSION" "$CURRENT_CHANGELOG")"
fi

vdf_escape "$APP_ID" APP_ID_VDF
vdf_escape "$PUBLISHED_FILE_ID" PUBLISHED_FILE_ID_VDF
vdf_escape "$CONTENT_DIR" CONTENT_FOLDER_VDF
vdf_escape "$CHANGE_NOTE" CHANGE_NOTE_VDF
vdf_escape "$VERSION" VERSION_VDF

APP_ID_VDF="$APP_ID_VDF" \
PUBLISHED_FILE_ID_VDF="$PUBLISHED_FILE_ID_VDF" \
CONTENT_FOLDER_VDF="$CONTENT_FOLDER_VDF" \
CHANGE_NOTE_VDF="$CHANGE_NOTE_VDF" \
VERSION_VDF="$VERSION_VDF" \
perl -pe '
    s/\{\{APP_ID\}\}/$ENV{APP_ID_VDF}/g;
    s/\{\{PUBLISHED_FILE_ID\}\}/$ENV{PUBLISHED_FILE_ID_VDF}/g;
    s/\{\{CONTENT_FOLDER\}\}/$ENV{CONTENT_FOLDER_VDF}/g;
    s/\{\{CHANGE_NOTE\}\}/$ENV{CHANGE_NOTE_VDF}/g;
    s/\{\{VERSION\}\}/$ENV{VERSION_VDF}/g;
' "$TEMPLATE" >"$VDF_FILE"

if grep -q '{{[^}]*}}' "$VDF_FILE"; then
    die "the generated VDF contains unresolved placeholders"
fi

printf '\nWorkshop release summary\n'
printf '  App ID:            %s\n' "$APP_ID"
printf '  Published file ID: %s\n' "$PUBLISHED_FILE_ID"
printf '  Version:           %s\n' "$VERSION"
printf '  Git commit:        %s\n' "$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
printf '  Change note:\n'
printf '%s\n' "$CHANGE_NOTE" | sed 's/^/    /'
printf '\nPayload files:\n'
(
    cd "$CONTENT_DIR"
    find . -type f -print | LC_ALL=C sort
)
printf '\nGenerated VDF:\n'
sed 's/^/  /' "$VDF_FILE"

if [[ "$DRY_RUN" == true ]]; then
    printf '\nDry run complete; SteamCMD was not invoked.\n'
    exit 0
fi

if [[ "$ASSUME_YES" != true ]]; then
    [[ -t 0 ]] || die "interactive confirmation requires a TTY; rerun with --yes after reviewing a dry run"
    printf '\nType %s to publish: ' "$PUBLISHED_FILE_ID"
    IFS= read -r confirmation
    [[ "$confirmation" == "$PUBLISHED_FILE_ID" ]] || die "publication cancelled"
fi

"$STEAMCMD" \
    +@ShutdownOnFailedCommand 1 \
    +@NoPromptForPassword 1 \
    +login "$STEAM_USER" \
    +workshop_build_item "$VDF_FILE" \
    +quit

printf '\nSteamCMD finished publishing Workshop item %s.\n' "$PUBLISHED_FILE_ID"
