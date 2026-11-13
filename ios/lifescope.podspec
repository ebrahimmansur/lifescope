Pod::Spec.new do |s|
  s.name             = 'lifescope'
  s.version          = '0.1.0'
  s.summary          = 'Composable application lifecycle management for Flutter.'
  s.description      = <<-DESC
Requests extra background time on iOS while lifescope callbacks finish.
                       DESC
  s.homepage         = 'https://github.com/ebrahimmansur/lifescope'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ebrahim Mansur' => '' }
  s.source           = { :path => '.' }
  s.source_files     = 'lifescope/Sources/lifescope/**/*.swift'
  s.resource_bundles = { 'lifescope_privacy' => ['lifescope/Sources/lifescope/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
