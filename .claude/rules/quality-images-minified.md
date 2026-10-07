---
title: Every Image Is as Small as It Can Be Without Showing It
impact: MEDIUM
impactDescription: Lossless optimisation alone took the docs images and tiles from 4.9 MiB to 3.2 MiB with identical pixels
tags: [quality, images, assets, size, png, webp]
paths: ["docs/**", "README.md", "savers/*/Resources/**"]
---

## Every Image Is as Small as It Can Be Without Showing It

**Impact: MEDIUM**

The images here are presentation: the README hero and each saver's page in
`docs/`, and the System Settings tiles in `savers/<name>/Resources/`. Each is
minified to the highest degree that introduces no visible artefact. In order:

1. **The right container.** The docs images are rendered scenes — gradients,
   glows, starfields — which is photographic content, so WebP or JPEG may be
   right for them. The tiles stay PNG: the build copies `thumbnail.png` and
   `thumbnail@2x.png` by name.
2. **Lossless first.** `oxipng -o max --strip safe` for PNG; `jpegtran
   -optimize -progressive` for JPEG. Identical pixels, smaller file.
3. **Then lossy, to the edge.** `cwebp -q 90 -m 6` or JPEG quality 85–90.
   Lower until an artefact shows, then back up one step.
4. **Look.** Side by side with the original at 1:1, on the busiest region —
   a starfield shows banding and lost stars before anything else does.

`make thumbnails` re-renders the tiles from scratch, so run the lossless step
again after it. Report the before and after sizes in the commit.

**Incorrect:**

```
docs/three-body.png   924 KiB   (never run through oxipng)
```

**Correct:**

```
docs/three-body.png   334 KiB   oxipng --strip safe (was 924 KiB); identical pixels
```

The figures above are the file before and after `oxipng -o max --strip safe`
(6 October 2026), with its pixels compared and found identical.
