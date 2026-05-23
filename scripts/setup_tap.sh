#!/bin/bash
# One-time setup: creates the homebrew-padvibe tap repo on GitHub and pushes the cask.
# Requires: gh CLI (brew install gh) and being logged in (gh auth login)

set -e

REPO="shabeer-wms/homebrew-padvibe"
CASK_SRC="$(dirname "$0")/../tap/Casks/padvibe.rb"
TMPDIR=$(mktemp -d)

echo "Creating GitHub repo: $REPO ..."
gh repo create "$REPO" \
  --public \
  --description "Homebrew tap for PadVibe" \
  --add-readme \
  || echo "Repo may already exist, continuing..."

echo "Cloning tap repo..."
gh repo clone "$REPO" "$TMPDIR/homebrew-padvibe"

mkdir -p "$TMPDIR/homebrew-padvibe/Casks"
cp "$CASK_SRC" "$TMPDIR/homebrew-padvibe/Casks/padvibe.rb"

cd "$TMPDIR/homebrew-padvibe"
git add Casks/padvibe.rb
git commit -m "Add PadVibe cask" || echo "Nothing to commit"
git push

echo ""
echo "Tap repo ready: https://github.com/$REPO"
echo ""
echo "Next steps:"
echo "  1. Add a GitHub secret HOMEBREW_TAP_TOKEN to the padvibe repo:"
echo "     https://github.com/shabeer-wms/padvibe/settings/secrets/actions"
echo "     (Use a PAT with 'repo' scope scoped to homebrew-padvibe)"
echo ""
echo "  2. Push a version tag to trigger a release:"
echo "     git tag v1.8.0 && git push origin v1.8.0"
echo ""
echo "  3. After the first release, users can install PadVibe with:"
echo "     brew tap shabeer-wms/padvibe"
echo "     brew install --cask padvibe"

rm -rf "$TMPDIR"
