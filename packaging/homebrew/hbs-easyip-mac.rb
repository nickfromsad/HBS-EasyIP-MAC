# Homebrew cask template. To offer `brew install --cask nickfromsad/tap/hbs-easyip-mac`:
#   1. Create a repo named "homebrew-tap" on GitHub with this file at Casks/hbs-easyip-mac.rb
#   2. After each release, update `version` and `sha256` (from SHA256SUMS.txt in the release)
cask "hbs-easyip-mac" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_OF_THE_DMG"

  url "https://github.com/nickfromsad/HBS---EasyIP-MAC/releases/download/v#{version}/HBS-EasyIP-MAC-#{version}.dmg"
  name "HBS // EasyIP MAC"
  desc "Find Panasonic PTZ cameras on any subnet and change their IP (Easy IP for macOS)"
  homepage "https://github.com/nickfromsad/HBS---EasyIP-MAC"

  depends_on macos: ">= :sonoma"

  app "HBS EasyIP MAC.app"
  binary "#{appdir}/HBS EasyIP MAC.app/Contents/MacOS/easyip"

  # Unsigned builds: remove the quarantine flag so the app opens without the Gatekeeper prompt.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/HBS EasyIP MAC.app"]
  end
end
