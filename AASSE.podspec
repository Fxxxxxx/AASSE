#
# Be sure to run `pod lib lint AASSE.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'AASSE'
  s.version          = '0.1.0'
  s.summary          = 'Swift 6 SSE SDK with AsyncStream and RFC compliance'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
AASSE is a Server-Sent Events (SSE) SDK for Swift 6, featuring:
- URLSession bytes streaming interface
- AsyncStream + enum callback pattern
- Full RFC 6202/HTML Living Standard compliance
- Objective-C bridge support
- Exponential backoff retry mechanism
- Comprehensive unit test coverage
                       DESC

  s.homepage         = 'https://github.com/Fxxxxxx/AASSE'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'AaronFeng' => 'aaronfeng1993@163.com' }
  s.source           = { :git => 'https://github.com/Fxxxxxx/AASSE.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '15.0'

  s.source_files = 'AASSE/Classes/**/*'
  s.swift_versions = '6.0'
  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'AASSE/Tests/**/*'
  end
  
  # s.resource_bundles = {
  #   'AASSE' => ['AASSE/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
