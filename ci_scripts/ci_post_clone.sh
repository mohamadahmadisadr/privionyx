#!/bin/sh
set -eu

# Xcode Cloud runs this after cloning the repository and before resolving packages.
#
# The project references LiteRT-LM as a *local* Swift package at LiteRT-LM/LiteRT-LM, and
# that directory is deliberately not committed: it is a large third-party checkout with its
# own nested .git. So a fresh clone — which is every Xcode Cloud build — has a package
# reference pointing at nothing, and resolution fails before a line is compiled. This puts
# the checkout back.
#
# Pinned to the same tag the app is developed against. A moving target here would mean the
# runtime under a shipped build is whatever HEAD happened to be that morning.

LITERT_LM_TAG="v0.13.1"
LITERT_LM_REPO="https://github.com/google-ai-edge/LiteRT-LM.git"
DESTINATION="$CI_PRIMARY_REPOSITORY_PATH/LiteRT-LM/LiteRT-LM"

if [ -d "$DESTINATION/.git" ]; then
    echo "LiteRT-LM already present at $DESTINATION"
    exit 0
fi

echo "Cloning LiteRT-LM $LITERT_LM_TAG into $DESTINATION"
mkdir -p "$(dirname "$DESTINATION")"

# --depth 1 against the tag: the build needs one revision's worth of source, not the history.
git clone --depth 1 --branch "$LITERT_LM_TAG" "$LITERT_LM_REPO" "$DESTINATION"

echo "LiteRT-LM $LITERT_LM_TAG ready"
