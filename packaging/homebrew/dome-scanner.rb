# Homebrew cask template. To offer `brew install --cask nickfromsad/tap/dome-scanner`:
#   1. Create a repo named "homebrew-tap" on GitHub with this file at Casks/dome-scanner.rb
#   2. After each release, update `version` and `sha256` (from SHA256SUMS.txt in the release)
cask "dome-scanner" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_OF_THE_DMG"

  url "https://github.com/nickfromsad/dome-scanner/releases/download/v#{version}/DomeScanner-#{version}.dmg"
  name "Dome Scanner"
  desc "Find Panasonic PTZ cameras on any subnet and change their IP (Easy IP for macOS)"
  homepage "https://github.com/nickfromsad/dome-scanner"

  depends_on macos: ">= :sonoma"

  app "Dome Scanner.app"
  binary "#{appdir}/Dome Scanner.app/Contents/MacOS/domescan"

  # Unsigned builds: remove the quarantine flag so the app opens without the Gatekeeper prompt.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Dome Scanner.app"]
  end
end
