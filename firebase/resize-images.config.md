# Firebase Resize Images Extension Configuration (T13.2)

This project uses Firebase Storage originals as source of truth, then serves transformed variants for feed/avatar surfaces.

## Recommended extension setup

- Extension: `storage-resize-images`
- Source bucket: default app Storage bucket
- Keep originals: enabled
- Delete resized images on original delete: enabled
- Output format: automatic or WebP-preferred when supported by the extension/runtime
- Resize trigger paths:
  - `gamePhotos/**`
  - `profilePhotos/**`

## Variant contract used by iOS

The iOS app expects Firebase-style resized object naming:

- Feed thumbnail: `<originalName>_400x400.<ext>`
- Avatar: `<originalName>_128x128.<ext>`

Configured in:

- `ios/bitchcup/bitchcup/App/ImageVariantURLBuilder.swift`

## Notes

- Originals remain the persisted `photoUrls` and `profilePhotoUrl` values.
- UI computes variant URLs at render time and falls back to originals on failure.
- Upload metadata sets `Cache-Control: public,max-age=31536000,immutable`.
