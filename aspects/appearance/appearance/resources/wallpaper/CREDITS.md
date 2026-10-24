# Wallpaper sources and licenses

Astra design, confirmed by the user on 2026-10-24. `render.py` implements the four
original compositions in [RECIPE.md](RECIPE.md) with the requested brighter
palette gradients and soft blue/cyan light. All source colors come from the
shared appearance palette. The PNGs are generated at build time, 2560×1600 sRGB.
No image service or generative image API is involved.

## Selected photography

The following photographs are downloaded directly from Unsplash's image CDN by
`fetchurl`. Each URL and SHA-256 is fixed in `package.nix`; no random/source API
is used. Outputs are 2560×1600 JPEG crops, quality 90. The mountain image is cropped toward the bottom to preserve the mountain/lake instead of showing only stars; the others use entropy crops. They retain the original
photographic colors rather than recoloring them to the application palette.
All four photo pages explicitly state **Unsplash License**, not Unsplash+.
Verified 2026-10-24. See [license terms](https://unsplash.com/license).

| Store filename | Author | Photo / original page | CDN image ID |
|---|---|---|---|
| ~~`12-starry-sea.jpg`~~ (removed from rotation: warm red cliff clashes with the cool palette) | Dima Kletsel | [The night sky over the ocean with stars above it](https://unsplash.com/photos/the-night-sky-over-the-ocean-with-stars-above-it-P3ojbX20pqY) | `photo-1674893798983-c64f80efc2f1` |
| `13-blue-city.jpg` | Tahsin Labib | [A city skyline illuminated at night with blue lights](https://unsplash.com/photos/a-city-skyline-illuminated-at-night-with-blue-lights--gyhqzDfDug) | `photo-1760421131154-f884a2e26b7e` |
| `14-night-coast.jpg` | Toby Yang | [A night time view of the ocean and the stars](https://unsplash.com/photos/a-night-time-view-of-the-ocean-and-the-stars-zFhLV5DSqWs) | `photo-1701497574685-1115c4ba215e` |
| `15-mountain-night.jpg` | Luke Miller | [The night sky over a mountain range and a body of water](https://unsplash.com/photos/the-night-sky-over-a-mountain-range-and-a-body-of-water-kf0FdiZy0uA) | `photo-1713769920897-eef95e8717f5` |

The existing repository images `002`, `005`, `008`, `009`, `011` remain in the
cool-toned rotation. Their original provenance was not recorded in this branch;
no new attribution is invented for them. Existing `001`, `004`, `006` and all
other original files remain untouched. User-provided images belong in
`~/Pictures/Wallpapers/local/` and are never fetched, copied into the store,
overwritten, or deleted by this factory.
