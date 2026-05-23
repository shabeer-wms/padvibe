cask "padvibe" do
  version "1.8.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/shabeer-wms/padvibe/releases/download/v#{version}/PadVibe-#{version}-Installer.dmg"
  name "PadVibe"
  desc "Zero-latency audio palette for podcasters, streamers, and creators"
  homepage "https://github.com/shabeer-wms/padvibe"

  app "PadVibe.app"

  zap trash: [
    "~/Library/Application Support/com.pro26.pads",
    "~/Library/Preferences/com.pro26.pads.plist",
    "~/Library/Saved Application State/com.pro26.pads.savedState",
  ]
end
