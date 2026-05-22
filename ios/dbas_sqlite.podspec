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
  s.source_files = 'dbas_sqlite/Sources/dbas_sqlite/**/*.swift'
  s.resource_bundles = {'dbas_sqlite_privacy' => ['dbas_sqlite/Sources/dbas_sqlite/PrivacyInfo.xcprivacy']}
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'

  s.swift_version = '5.0'
  s.vendored_frameworks = 'dbas_sqlite/dbas_sqlite.xcframework'
  s.libraries = 'c++'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-all_load',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES'
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-all_load'
  }
  s.static_framework = true
end
