
Pod::Spec.new do |s|
  s.name         = "MeteorSwiftTV"
  s.version      = "0.0.1"
  s.summary      = "A swifty implementation of client side Meteor for tvOS."
  s.description  = <<-DESC
                    A swift implementation of the Meteor client and DDP for use on tvOS.
                   DESC
  s.homepage     = "http://www.curlcoach.com"
  s.license      = "MIT"
  s.author       = { "Stephen Orr" => "stephen@chatorr.ca" }
  s.platform     = :tvos, "14.7"
  s.source       = { :git => "https://github.com/idelrich/MeteorSwift.git", :tag => "0.0.14" }
  s.source_files = "MeteorSwift/*.{swift,h}"
  s.dependency  "SocketRocket"
end

