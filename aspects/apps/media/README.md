# Media

Installs and configures media playback, capture, image viewing, music, and editing tools. `user.appearance` supplies mpv and Swayimg colors/fonts; mpv has portable fallback values when no palette is selected. Hardware decoding remains a host fact owned by the hardware feature.

Outputs include mpv with uosc/MPRIS/autoload/thumbnail scripts and Anime4K shaders, Musicfox, OBS with PipeWire/wlrobs/Vulkan capture plugins, Blender, GIMP, Kdenlive, FFmpeg, ImageMagick, Swayimg and libheif. The feature registers video and image MIME handlers and publishes a visible Swayimg desktop entry.

Owned files are `default.nix`, `blender.nix`, `images.nix`, `mpv.nix`, `musicfox.nix`, and `obs-studio.nix`; these Nix files are private. Removing the feature removes package, MIME, and configuration declarations, while media libraries, OBS profiles/recordings, Blender projects, images, and other user data remain on disk.
