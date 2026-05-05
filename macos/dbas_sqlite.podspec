#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint dbas_sqlite.podspec` to validate before publishing.
#
require 'yaml'
pubspec = YAML.load_file(File.join('..', 'pubspec.yaml'))

Pod::Spec.new do |s|
  s.name             = pubspec['name']
  s.version          = pubspec['version']
  s.summary          = pubspec['description']
  s.description      = pubspec['description']
  s.homepage         = pubspec['homepage']
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { pubspec['author_name'] => pubspec['author_email'] }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '13.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-all_load',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'MACOSX_DEPLOYMENT_TARGET' => '13.0'
  }
  s.user_target_xcconfig = {
    # `-lc++` is also declared via `s.libraries = 'c++'` below, but
    # CocoaPods has historically not propagated `s.libraries` to the
    # consumer target when the pod is a static framework
    # (`s.static_framework = true`). Stating it here explicitly forces
    # the Runner's link line to include libc++, which is required for
    # the static lib's STL symbols (std::__1::*, ___cxa_throw,
    # ___gxx_personality_v0, etc.) to resolve.
    'OTHER_LDFLAGS' => '-all_load -lc++',
    'MACOSX_DEPLOYMENT_TARGET' => '13.0'
  }
  s.swift_version = '5.0'
  s.vendored_frameworks = 'macos/dbas_sqlite.xcframework'
  # The vendored static lib is C++ (uses libc++ STL: std::chrono, hash maps,
  # std::__throw_bad_array_new_length, __cxa_throw). Without `s.libraries =
  # 'c++'`, CocoaPods doesn't pass `-lc++` to the linker and Runner fails with
  # `Undefined symbols for architecture arm64: std::__1::*` / `___cxa_throw`.
  # iOS podspec already does this — keep both in sync.
  s.libraries = 'c++'
  s.static_framework = true

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'dbas_sqlite_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
