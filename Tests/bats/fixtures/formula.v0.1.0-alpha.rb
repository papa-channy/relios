class Relios < Formula
  desc "Local release pipeline CLI for SwiftPM macOS apps"
  homepage "https://github.com/papa-channy/relios"
  url "https://github.com/papa-channy/relios/archive/refs/tags/v0.1.0-alpha.tar.gz"
  sha256 "0f384f1697ca4264af0c8b58743ab9f2d473750f9c37239a3ae193148514f00c"
  license "MIT"
  head "https://github.com/papa-channy/relios.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/relios"
  end

  test do
    assert_match "relios", shell_output("#{bin}/relios --help")
  end
end
