#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint nmtk_wgpu_renderer_plugin.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'nmtk_wgpu_renderer_plugin'
  s.version          = '0.1.0'
  s.summary          = 'Native wgpu neuron renderer texture bridge.'
  s.description      = <<-DESC
Registers the CVPixelBuffer produced by the nmtk_wgpu Rust renderer as a
Flutter Texture. Builds the nmtk_wgpu crate (neurocnl/frontend/rust/nmtk_wgpu)
via cargo as part of the Xcode build.
                       DESC
  s.homepage         = 'https://github.com/nmtk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'NMTK' => 'noreply@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'nmtk_wgpu_renderer_plugin/Sources/nmtk_wgpu_renderer_plugin/**/*'

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  # Builds the nmtk_wgpu Rust crate and drops the dylib at a fixed path
  # inside this pod's own source tree, which `vendored_libraries` below
  # references. A dylib must already exist there the first time `pod install`
  # runs (CocoaPods validates the path at install time) — this script keeps
  # it up to date on every subsequent Xcode build, but does not satisfy that
  # first-run requirement by itself.
  # ponytail: script_phase + vendored_libraries is the simplest thing that
  # works for one platform; if it proves too fragile in CI, fall back to a
  # `cargo build` step in run_dev.sh/Makefile before `pod install` instead.
  #
  # Release builds produce a universal (arm64 + x86_64) dylib for Intel Mac
  # support. Debug builds only build the host architecture — requiring the
  # x86_64-apple-darwin target/std to be installed just to run `flutter run`
  # locally on an Apple Silicon dev machine (or vice versa) is unnecessary
  # and was blocking local debug builds on machines without that target
  # installed (Homebrew's rust doesn't ship secondary targets; only rustup
  # does).
  s.vendored_libraries = 'libnmtk_wgpu.dylib'
  s.script_phase = {
    :name => 'Build nmtk_wgpu (cargo)',
    :execution_position => :before_compile,
    :script => <<-SCRIPT
      set -euo pipefail
      REPO_ROOT="$(cd "${PODS_TARGET_SRCROOT}" && git rev-parse --show-toplevel)"
      CRATE_DIR="${REPO_ROOT}/neurocnl/frontend/rust/nmtk_wgpu"
      PROFILE_DIR="debug"
      EXTRA_FLAGS=""
      if [ "${CONFIGURATION}" = "Release" ]; then
        PROFILE_DIR="release"
        EXTRA_FLAGS="--release"
      fi

      export PATH="$HOME/.cargo/bin:$PATH"
      cd "${CRATE_DIR}"

      OUT="${PODS_TARGET_SRCROOT}/libnmtk_wgpu.dylib"
      if [ "${CONFIGURATION}" = "Release" ]; then
        cargo build ${EXTRA_FLAGS} --target aarch64-apple-darwin
        cargo build ${EXTRA_FLAGS} --target x86_64-apple-darwin
        lipo -create \\
          "target/aarch64-apple-darwin/${PROFILE_DIR}/libnmtk_wgpu.dylib" \\
          "target/x86_64-apple-darwin/${PROFILE_DIR}/libnmtk_wgpu.dylib" \\
          -output "${OUT}"
      else
        HOST_TARGET="x86_64-apple-darwin"
        if [ "$(uname -m)" = "arm64" ]; then
          HOST_TARGET="aarch64-apple-darwin"
        fi
        cargo build --target "${HOST_TARGET}"
        cp "target/${HOST_TARGET}/${PROFILE_DIR}/libnmtk_wgpu.dylib" "${OUT}"
      fi
      install_name_tool -id "@rpath/libnmtk_wgpu.dylib" "${OUT}"
    SCRIPT
  }
end
