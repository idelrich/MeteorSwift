
Pod::Spec.new do |s|
  s.name         = "MeteorSwift"
  s.version      = "0.0.1"
  s.summary      = "A swifty implementation of client side Meteor for iOS."
  s.description  = <<-DESC
                    A swift implementation of the Meteor client and DDP for use on iOS.
                   DESC
  s.homepage     = "http://www.curlcoach.com"
  s.license      = "MIT"
  s.author       = { "Stephen Orr" => "stephen@chatorr.ca" }
  s.platform     = :ios, "10.0"
  s.source       = { :git => "https://Stephen-Orr@bitbucket.org/Stephen-Orr/meteorswift.git", :tag => "1.0.0" }
  s.source_files = "MeteorSwift/*.swift", "MeteorSwift/*.h"
  s.dependency   "SocketRocket"
  s.dependency   "SCrypto"
end

