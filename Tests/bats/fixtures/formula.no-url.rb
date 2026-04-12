class Relios < Formula
  desc "Local release pipeline CLI for SwiftPM macOS apps"
  homepage "https://github.com/papa-channy/relios"
  sha256 "0f384f1697ca4264af0c8b58743ab9f2d473750f9c37239a3ae193148514f00c"
  license "MIT"

  def install
    bin.install "relios"
  end
end
