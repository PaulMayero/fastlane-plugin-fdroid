lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fastlane/plugin/fdroid/version'

Gem::Specification.new do |spec|
  spec.name          = 'fastlane-plugin-fdroid'
  spec.version       = Fastlane::Fdroid::VERSION
  spec.author        = 'F-Droid'
  spec.email         = 'fdroid@fdroid.com'

  spec.summary       = 'opens a PR for an app to be packaged on F-Droid'
  spec.homepage      = "https://github.com/PaulMayero/fastlane-plugin-fdroid"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*"] + %w(README.md LICENSE)
  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.required_ruby_version = '>= 2.6'

  # Don't add a dependency to fastlane or fastlane_re
  # since this would cause a circular dependency

  spec.add_dependency 'gitlab', '~> 5.0'
  spec.add_dependency 'pry'
  spec.add_dependency 'pry-byebug'
  spec.add_dependency 'nokogiri', '~> 1.18'
  spec.add_dependency 'http-cookie', '~> 1.0'
  spec.add_dependency 'octokit'
  spec.add_dependency 'rugged'
  spec.add_dependency 'rbnacl'
  spec.post_install_message = <<~MSG
  NOTE: Rugged may require native extensions.
  If you're using SSH support, install it with:

    gem install rugged -- --with-ssh
  MSG
end
