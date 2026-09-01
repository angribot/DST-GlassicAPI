#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
readonly APP_ID="322330"
CONFIG="$SCRIPT_DIR/config.json"

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

Required:
  jq                       Available in PATH
  steam-workshop-uploader  Available in PATH unless using --dry-run

Options:
  --changenote NOTE  Override the update note; NOTE may contain newlines
  --dry-run          Build and inspect the payload without invoking the uploader
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

generate_vdf() {
    cat >"$VDF_FILE" <<EOF
"workshopitem"
{
    "appid"           "$APP_ID_VDF"
    "publishedfileid" "$PUBLISHED_FILE_ID_VDF"
    "contentfolder"   "$CONTENT_FOLDER_VDF"
    "changenote"      "$CHANGE_NOTE_VDF"

    "tags"
    {
$TAGS_VDF
    }
}
EOF
}

generate_mod_manifest() {
    local content_dir="$1"

    MOD_CONTENT_DIR="$content_dir" perl -MFile::Find -e '
        use strict;
        use warnings;
        use bytes;

        my $root = $ENV{MOD_CONTENT_DIR};
        my @paths;

        find(
            {
                no_chdir => 1,
                wanted => sub {
                    return unless -f $File::Find::name;

                    my $path = $File::Find::name;
                    my $prefix = "$root/";
                    die "payload file is outside its root: $path\n"
                        unless index($path, $prefix) == 0;

                    $path = substr($path, length($prefix));
                    $path =~ tr{\\}{/};
                    return if $path eq "mod.manifest";
                    push @paths, $path;
                },
            },
            $root,
        );

        @paths = sort { $a cmp $b } @paths;
        die "payload contains no files\n" unless @paths;

        # Klei mod.manifest v1: "MNFS" + LE32 version + LE32 file count,
        # followed by one LE32 SDBM hash per lowercase payload-relative path.
        open my $manifest, ">:raw", "$root/mod.manifest"
            or die "could not create mod.manifest: $!\n";
        print {$manifest} "MNFS", pack("V2", 1, scalar @paths)
            or die "could not write mod.manifest: $!\n";

        for my $path (@paths) {
            my $hash = 0;
            for my $byte (unpack("C*", lc $path)) {
                $hash = ($byte + $hash * 65599) & 0xffffffff;
            }
            print {$manifest} pack("V", $hash)
                or die "could not write mod.manifest: $!\n";
        }

        close $manifest or die "could not close mod.manifest: $!\n";
    '
}

extract_current_changelog() {
    perl -0777 -e '
        $_ = <>;
        my @matches = /changelog\s*=\s*zheng\s*\(\s*\[\[(.*?)\]\]\s*,\s*\[\[(.*?)\]\]\s*\)/sg;
        exit 1 unless @matches == 2;

        my $changelog = $matches[1];
        $changelog =~ s/\A(?:[\t ]*\n)+//;
        $changelog =~ s/(?:\n[\t ]*)+\z//;
        $changelog =~ s/\n[\t ]*(?i:Recent Changes):[\t ]*(?:\n|\z).*//s;
        $changelog =~ s/(?:\n[\t ]*)+\z//;
        exit 1 unless $changelog =~ /\S/;

        print $changelog;
    ' "$1"
}

extract_mod_type() {
    perl -0777 -e '
        use strict;
        use warnings;

        my $source = <>;
        my @fields = qw(client_only_mod all_clients_require_mod);
        my (%occurrences, %declarations, %values);

        sub blank {
            my ($text) = @_;
            $text =~ s/[^\r\n]/ /g;
            return $text;
        }

        # Blank comments and strings before looking for assignments. Newlines are
        # retained so declarations must still occupy their own source line.
        $source =~ s{(?:--)?\[(=*)\[.*?\]\1\]}{blank($&)}gse;
        $source =~ s{"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27}{blank($&)}gse;
        $source =~ s{--[^\r\n]*}{blank($&)}ge;

        for my $field (@fields) {
            $occurrences{$field}++ while $source =~ /\b\Q$field\E[\t ]*=/g;
        }

        while ($source =~ /^[\t ]*(client_only_mod|all_clients_require_mod)[\t ]*=[\t ]*([^\r\n]*)/mg) {
            my ($field, $value) = ($1, $2);
            $declarations{$field}++;
            $value =~ s/[\t ]*;?[\t ]*\z//;

            die "$field must be assigned the literal true or false\n"
                unless $value eq "true" || $value eq "false";
            die "$field must not be declared more than once\n"
                if $declarations{$field} > 1;

            $values{$field} = $value;
        }

        for my $field (@fields) {
            die "$field must be a top-level literal assignment\n"
                if ($occurrences{$field} // 0) != ($declarations{$field} // 0);
        }

        my $client_only = ($values{client_only_mod} // "false") eq "true";
        my $all_clients = ($values{all_clients_require_mod} // "false") eq "true";
        die "client_only_mod and all_clients_require_mod must not both be true\n"
            if $client_only && $all_clients;

        print $client_only
            ? "client_only_mod"
            : $all_clients
                ? "all_clients_require_mod"
                : "server_only_mod";
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

command -v jq >/dev/null 2>&1 || die "jq is required but was not found in PATH"
[[ -f "$CONFIG" ]] || die "Workshop config not found: $CONFIG"

if ! jq -e '
    if type != "object" then
        error("root must be an object")
    elif keys != ["publishedFileId", "tags"] then
        error("only publishedFileId and tags are allowed")
    elif (.publishedFileId | type) != "number"
        or (.publishedFileId | floor) != .publishedFileId
        or .publishedFileId <= 0 then
        error("publishedFileId must be an integer greater than zero")
    elif (.tags | type) != "array" then
        error("tags must be an array")
    elif any(.tags[]; type != "string") then
        error("every tag must be a string")
    elif any(.tags[]; length == 0) then
        error("tags must not be empty")
    elif any(.tags[]; test("^\\s|\\s$")) then
        error("tags must not have leading or trailing whitespace")
    elif any(.tags[]; test("[[:cntrl:]]")) then
        error("tags must not contain control characters")
    elif (.tags | length) != (.tags | unique | length) then
        error("tags must not contain duplicates")
    elif any(.tags[]; test("^(client_only_mod|all_clients_require_mod|server_only_mod)$"; "i")) then
        error("type tags are generated automatically from modinfo.lua")
    elif any(.tags[]; test("^version:"; "i")) then
        error("version tags are generated automatically")
    else
        true
    end
' "$CONFIG" >/dev/null; then
    die "invalid Workshop config: $CONFIG"
fi

PUBLISHED_FILE_ID="$(jq -r '.publishedFileId | tostring' "$CONFIG")"
[[ "$PUBLISHED_FILE_ID" =~ ^[1-9][0-9]*$ ]] || die "publishedFileId must use decimal integer notation"
readonly PUBLISHED_FILE_ID

[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || die "working tree is not clean"

for required_path in modinfo.lua modmain.lua; do
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
    if [[ "$object_type" == tree || "$content_path" == *.lua || "$content_path" == *.xml || "$content_path" == *.tex ]]; then
        CONTENT_PATHS+=("$content_path")
    fi
done < <(git -C "$REPO_ROOT" ls-tree -z HEAD)

((${#CONTENT_PATHS[@]} > 0)) || die "HEAD contains no publishable top-level directories or Lua, XML, or TeX files"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/workshop-${APP_ID}-XXXXXX")"
trap cleanup EXIT HUP INT TERM
readonly CONTENT_DIR="$WORK_DIR/content"
readonly VDF_FILE="$WORK_DIR/item.vdf"
mkdir -p "$CONTENT_DIR"

git -C "$REPO_ROOT" archive --format=tar HEAD -- "${CONTENT_PATHS[@]}" | tar -xf - -C "$CONTENT_DIR"

if ! generate_mod_manifest "$CONTENT_DIR"; then
    die "could not generate mod.manifest"
fi
[[ -s "$CONTENT_DIR/mod.manifest" ]] || die "generated mod.manifest is empty"

VERSION="$(awk -F'"' '/^[[:space:]]*version[[:space:]]*=[[:space:]]*"/ { print $2; exit }' "$CONTENT_DIR/modinfo.lua")"
[[ -n "$VERSION" ]] || die "could not read version from modinfo.lua"

MOD_TYPE="$(extract_mod_type "$CONTENT_DIR/modinfo.lua")" || die "could not determine mod type from modinfo.lua"
readonly MOD_TYPE

if [[ "$CHANGE_NOTE_SET" == true ]]; then
    CHANGE_NOTE="${CHANGE_NOTE//$'\r\n'/$'\n'}"
    [[ "$CHANGE_NOTE" != *$'\r'* ]] || die "--changenote contains an unsupported carriage return"
    [[ "$CHANGE_NOTE" =~ [^[:space:]] ]] || die "--changenote must not be empty"
else
    CURRENT_CHANGELOG="$(extract_current_changelog "$CONTENT_DIR/modinfo.lua")" || \
        die "could not read the current English changelog from modinfo.lua"
    CHANGE_NOTE="$(printf 'Version: %s\n\nChanges:\n%s' "$VERSION" "$CURRENT_CHANGELOG")"
fi

TAGS_VDF=""
TAG_VDF=""
TAG_ENTRY=""
TAG_INDEX=0
while IFS= read -r tag; do
    vdf_escape "$tag" TAG_VDF
    printf -v TAG_ENTRY '        "%s" "%s"' "$TAG_INDEX" "$TAG_VDF"
    TAGS_VDF+="${TAGS_VDF:+$'\n'}$TAG_ENTRY"
    TAG_INDEX=$((TAG_INDEX + 1))
done < <(jq -r '.tags[]' "$CONFIG")

vdf_escape "$MOD_TYPE" TAG_VDF
printf -v TAG_ENTRY '        "%s" "%s"' "$TAG_INDEX" "$TAG_VDF"
TAGS_VDF+="${TAGS_VDF:+$'\n'}$TAG_ENTRY"
TAG_INDEX=$((TAG_INDEX + 1))

vdf_escape "version:$VERSION" TAG_VDF
printf -v TAG_ENTRY '        "%s" "%s"' "$TAG_INDEX" "$TAG_VDF"
TAGS_VDF+="${TAGS_VDF:+$'\n'}$TAG_ENTRY"

vdf_escape "$APP_ID" APP_ID_VDF
vdf_escape "$PUBLISHED_FILE_ID" PUBLISHED_FILE_ID_VDF
vdf_escape "$CONTENT_DIR" CONTENT_FOLDER_VDF
vdf_escape "$CHANGE_NOTE" CHANGE_NOTE_VDF

generate_vdf

printf '\nWorkshop release summary\n'
printf '  App ID:            %s\n' "$APP_ID"
printf '  Published file ID: %s\n' "$PUBLISHED_FILE_ID"
printf '  Version:           %s\n' "$VERSION"
printf '  Mod type:          %s\n' "$MOD_TYPE"
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
    printf '\nDry run complete; uploader was not invoked.\n'
    exit 0
fi

if [[ "$ASSUME_YES" != true ]]; then
    [[ -t 0 ]] || die "interactive confirmation requires a TTY; rerun with --yes after reviewing a dry run"
    printf '\nType %s to publish: ' "$PUBLISHED_FILE_ID"
    IFS= read -r confirmation
    [[ "$confirmation" == "$PUBLISHED_FILE_ID" ]] || die "publication cancelled"
fi

steam-workshop-uploader "$VDF_FILE"

printf '\nUploader finished publishing Workshop item %s.\n' "$PUBLISHED_FILE_ID"
