#!/usr/bin/env bash
set -euo pipefail

# Deletes test documents from Firestore collections and related Storage photos.
# Keeps collections themselves (they remain, but empty).
#
# Usage:
#   ./cleanup-test-data.sh --project bitchcup-dev --bucket bitchcup-dev.firebasestorage.app
# Optional:
#   --include-profile-photos   Also delete /profilePhotos objects.
#   --yes                      Skip interactive confirmation prompt.
#
# Requirements:
#   - Firebase CLI installed and logged in (`firebase login`)
#   - Permissions for Firestore + Storage delete in the target project

PROJECT_ID=""
BUCKET=""
INCLUDE_PROFILE_PHOTOS="false"
ASSUME_YES="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_ID="${2:-}"
      shift 2
      ;;
    --bucket)
      BUCKET="${2:-}"
      shift 2
      ;;
    --include-profile-photos)
      INCLUDE_PROFILE_PHOTOS="true"
      shift
      ;;
    --yes)
      ASSUME_YES="true"
      shift
      ;;
    -h|--help)
      sed -n 's/^# \{0,1\}//p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ID" || -z "$BUCKET" ]]; then
  echo "Error: --project and --bucket are required." >&2
  echo "Example: ./cleanup-test-data.sh --project bitchcup-dev --bucket bitchcup-dev.firebasestorage.app" >&2
  exit 1
fi

echo "Project: $PROJECT_ID"
echo "Bucket:  $BUCKET"
echo "This will DELETE all documents in:"
echo "  - communities"
echo "  - memberships"
echo "  - gameLogs"
echo "And DELETE Storage objects under:"
echo "  - /gamePhotos"
if [[ "$INCLUDE_PROFILE_PHOTOS" == "true" ]]; then
  echo "  - /profilePhotos"
fi
echo
echo "Collections will remain but be emptied."

if [[ "$ASSUME_YES" != "true" ]]; then
  read -r -p "Type DELETE to continue: " CONFIRM
  if [[ "$CONFIRM" != "DELETE" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "Deleting Firestore docs..."
firebase --project "$PROJECT_ID" firestore:delete communities --recursive
firebase --project "$PROJECT_ID" firestore:delete memberships --recursive
firebase --project "$PROJECT_ID" firestore:delete gameLogs --recursive

echo "Deleting Storage photos..."
firebase --project "$PROJECT_ID" storage:delete "gs://$BUCKET/gamePhotos/**" || true
if [[ "$INCLUDE_PROFILE_PHOTOS" == "true" ]]; then
  firebase --project "$PROJECT_ID" storage:delete "gs://$BUCKET/profilePhotos/**" || true
fi

echo "Done."
