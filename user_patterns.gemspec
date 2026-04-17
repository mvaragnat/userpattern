# frozen_string_literal: true

require_relative 'lib/user_patterns/version'

Gem::Specification.new do |spec|
  spec.name = 'user_patterns'
  spec.version = UserPatterns::VERSION
  spec.authors = ['UserPatterns Contributors']
  spec.email = []

  spec.summary = 'Anonymized usage pattern analysis for Rails applications'
  spec.description = 'Track and analyze endpoint usage patterns of logged-in users ' \
                     'with full anonymization. Block suspicious behaviors that deviate ' \
                     'from normal patterns. Complementary with RackAttack.'
  spec.homepage = 'https://github.com/mvaragnat/user_patterns'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir[
    'lib/**/*',
    'app/**/*',
    'config/**/*',
    'README.md',
    'LICENSE'
  ]
  spec.require_paths = ['lib']

  spec.add_dependency 'concurrent-ruby', '>= 1.1'
  spec.add_dependency 'rails', '>= 7.0'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
