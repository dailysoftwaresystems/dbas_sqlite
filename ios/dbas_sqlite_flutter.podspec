#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint dbas_sqlite_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'dbas_sqlite_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin that access SQLite for Android, iOS, macOS, Linux, Windows and Web.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'https://github.com/dailysoftwaresystems/DBAS.SQLite.Flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Daily Software Systems LTDA.' => 'dailysoftwaresystems@outlook.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.vendored_frameworks = 'dbas_sqlite.xcframework'
  s.static_framework = true

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'dbas_sqlite_flutter_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
