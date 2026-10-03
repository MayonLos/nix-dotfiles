{ tesseract5 }:

# English + Simplified Chinese traineddata. nixpkgs builds tesseract with
# English only; chi_sim is the case that actually comes up here, and the
# language set is baked in at build time, so adding one later means a rebuild.
# Shared by modules/home/packages.nix and apps/screenshot.nix so Chinese OCR
# cannot silently run against the wrong build.
tesseract5.override {
  enableLanguages = [
    "eng"
    "chi_sim"
  ];
}
