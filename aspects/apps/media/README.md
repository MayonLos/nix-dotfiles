# Media

Installs and configures media playback, capture, image viewing, music, and editing tools. `user.appearance` supplies mpv and Swayimg colors/fonts; mpv retains its packaged color defaults when no palette is selected. Hardware decoding remains a host fact owned by the hardware feature.

Outputs include mpv with uosc/MPRIS/autoload/thumbnail scripts and Anime4K shaders, Musicfox, OBS with PipeWire/wlrobs/Vulkan capture plugins, Blender, GIMP, Kdenlive, FFmpeg, ImageMagick, Swayimg and libheif. The feature registers video and image MIME handlers and publishes a visible Swayimg desktop entry.

mpv subtitles and OSD use bright text with a deep outline. uosc uses neutral selection fills, bright text, an 8 px native radius, and blue search matches; a bounded uosc 5.12 theme adaptation separates selection fills from icon/progress foregrounds (the upstream menu highlight opacity is retained). The adaptation fails to build if the expected upstream snippets change. Swayimg uses opaque info labels and a 2 px blue gallery outline.

Owned files are `default.nix`, `blender.nix`, `images.nix`, `mpv.nix`, `musicfox.nix`, and `obs-studio.nix`; these Nix files are private. Removing the feature removes package, MIME, and configuration declarations, while media libraries, OBS profiles/recordings, Blender projects, images, and other user data remain on disk.
