Pod::Spec.new do |s|
  s.name             = 'text_reader'
  s.version          = '0.1.0'
  s.summary          = 'On-device text recognition with Apple Vision.'
  s.homepage         = 'https://github.com'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Owned' => 'owned' }
  s.source           = { :path => '.' }
  s.source_files     = 'text_reader/Sources/text_reader/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
end
