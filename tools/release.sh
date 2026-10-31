#!/usr/bin/env bash
# Builds Normandy 1944 for macOS and Windows and publishes them as a GitHub release.
#
#   tools/release.sh               build both, then create release v<version> on GitHub
#   tools/release.sh --build-only  build both zips into build/release/, publish nothing
#   tools/release.sh --draft       create the release as a draft, to look over before publishing
#
# The version comes from application/config/version in project.godot; bump it there (and commit) before
# releasing. The release is tagged v<version> at the current commit, which has to be pushed already.
# Needs Godot 4.7 (found as $GODOT, ~/Downloads/Godot.app, /Applications/Godot.app or `godot` on the PATH)
# and, to publish, the GitHub CLI (`gh`) logged in. Missing export templates are downloaded once.
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_ONLY=0
DRAFT=()
for arg in "$@"; do
	case "$arg" in
		--build-only) BUILD_ONLY=1 ;;
		--draft) DRAFT=(--draft) ;;
		-h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
	esac
done

fail() { echo "error: $*" >&2; exit 1; }

# --- Godot and its export templates ---

GODOT="${GODOT:-}"
if [[ -z "$GODOT" ]]; then
	for candidate in "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" "/Applications/Godot.app/Contents/MacOS/Godot" "$(command -v godot || true)"; do
		if [[ -n "$candidate" && -x "$candidate" ]]; then GODOT="$candidate"; break; fi
	done
fi
[[ -n "$GODOT" && -x "$GODOT" ]] || fail "Godot not found; set GODOT=/path/to/Godot"

# "4.7.2.stable.official.ed1daf0bf" -> templates folder "4.7.2.stable", download tag "4.7.2-stable".
GODOT_VERSION="$("$GODOT" --version | head -1)"
TEMPLATE_VERSION="$(echo "$GODOT_VERSION" | cut -d. -f1-4)"
[[ "$TEMPLATE_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?\.[a-z0-9]+$ ]] || fail "Can't read the Godot version from '$GODOT_VERSION'"
TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates/$TEMPLATE_VERSION"
NEEDED_TEMPLATES=(macos.zip windows_release_x86_64.exe)

missing_templates=()
for template in "${NEEDED_TEMPLATES[@]}"; do
	[[ -f "$TEMPLATE_DIR/$template" ]] || missing_templates+=("$template")
done
if (( ${#missing_templates[@]} )); then
	release_tag="${TEMPLATE_VERSION%.*}-${TEMPLATE_VERSION##*.}"
	url="https://github.com/godotengine/godot/releases/download/$release_tag/Godot_v${release_tag}_export_templates.tpz"
	echo "Downloading the Godot $release_tag export templates (about 1 GB, only once) for: ${missing_templates[*]}"
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT
	curl -fL --progress-bar -o "$tmp/templates.tpz" "$url" || fail "Couldn't download $url"
	mkdir -p "$TEMPLATE_DIR"
	for template in "${missing_templates[@]}"; do
		unzip -q -j -o "$tmp/templates.tpz" "templates/$template" -d "$TEMPLATE_DIR" || fail "$template isn't in the template pack"
	done
	echo "$TEMPLATE_VERSION" > "$TEMPLATE_DIR/version.txt"
	rm -rf "$tmp"
	trap - EXIT
fi

# --- Version and release checks ---

VERSION="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot)"
[[ -n "$VERSION" ]] || fail "No config/version in project.godot"
TAG="v$VERSION"

if (( ! BUILD_ONLY )); then
	command -v gh >/dev/null || fail "The GitHub CLI (gh) is needed to publish; install it or use --build-only"
	gh auth status >/dev/null 2>&1 || fail "gh isn't logged in; run: gh auth login"
	[[ -z "$(git status --porcelain)" ]] || fail "Uncommitted changes; commit them first so the release matches its tag"
	git fetch --quiet --tags origin
	if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || gh release view "$TAG" >/dev/null 2>&1; then
		fail "$TAG already exists; bump config/version in project.godot"
	fi
	COMMIT="$(git rev-parse HEAD)"
	[[ -n "$(git branch -r --contains "$COMMIT")" ]] || fail "The current commit isn't pushed; push it first"
fi

# --- Build ---

OUT="build/release"
rm -rf "$OUT" "build/Normandy 1944.app" "build/windows"
mkdir -p "$OUT" "build/windows"
MAC_ZIP="$OUT/Normandy-1944-$TAG-macos.zip"
WIN_ZIP="$OUT/Normandy-1944-$TAG-windows.zip"

export_preset() {
	local preset="$1" path="$2" log="$OUT/export-${1// /-}.log"
	echo "Exporting $preset..."
	if ! "$GODOT" --headless --path . --export-release "$preset" "$path" >"$log" 2>&1 || [[ ! -e "$path" ]]; then
		tail -20 "$log" >&2
		fail "The $preset export failed (full log: $log)"
	fi
}

export_preset "macOS" "build/Normandy 1944.app"
# Ad-hoc signature so Apple silicon runs it; it isn't notarized, so the first launch needs right-click > Open.
codesign --force --deep -s - "build/Normandy 1944.app"
ditto -c -k --keepParent "build/Normandy 1944.app" "$MAC_ZIP"

export_preset "Windows Desktop" "build/windows/Normandy 1944.exe"
(cd build/windows && zip -q -r "../../$WIN_ZIP" "Normandy 1944.exe")

echo "Built:"
ls -lh "$MAC_ZIP" "$WIN_ZIP" | awk '{print "  " $5 "  " $NF}'

if (( BUILD_ONLY )); then
	exit 0
fi

# --- Publish ---

NOTES="$(cat <<EOF
## Download

- **macOS** (Apple silicon and Intel, macOS 11+): \`$(basename "$MAC_ZIP")\`. Unzip and open *Normandy 1944*. It isn't notarized, so the first time right-click the app and choose **Open**.
- **Windows** (64-bit): \`$(basename "$WIN_ZIP")\`. Unzip and run *Normandy 1944.exe*. It isn't signed, so SmartScreen may warn: choose **More info**, then **Run anyway**.
EOF
)"

echo "Creating release $TAG on GitHub..."
gh release create "$TAG" "$MAC_ZIP" "$WIN_ZIP" \
	--target "$COMMIT" \
	--title "Normandy 1944 $TAG" \
	--notes "$NOTES" \
	--generate-notes \
	"${DRAFT[@]+"${DRAFT[@]}"}"
