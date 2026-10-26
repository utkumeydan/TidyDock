# Copy to github.com/utkumeydan/homebrew-tap as Casks/tidydock.rb.
# The release workflow prints the version and sha256 for each release.
cask "tidydock" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE"

  url "https://github.com/utkumeydan/TidyDock/releases/download/v#{version}/TidyDock-#{version}.zip"
  name "TidyDock"
  desc "Quits apps when their last window closes"
  homepage "https://github.com/utkumeydan/TidyDock"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :ventura"

  app "TidyDock.app"

  uninstall quit: "io.github.utkumeydan.TidyDock",
            login_item: "TidyDock"

  zap trash: [
    "~/Library/Preferences/io.github.utkumeydan.TidyDock.plist",
    "~/Library/Caches/io.github.utkumeydan.TidyDock",
    "~/Library/HTTPStorages/io.github.utkumeydan.TidyDock",
  ]

  caveats <<~EOS
    TidyDock is not notarized by Apple. If macOS blocks it on first launch, open
    System Settings › Privacy & Security and click "Open Anyway", or run:
      xattr -dr com.apple.quarantine #{appdir}/TidyDock.app
  EOS
end
