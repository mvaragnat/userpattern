# frozen_string_literal: true

require_relative 'lib/userpattern/version'

Gem::Specification.new do |spec|
  spec.name = 'userpattern'
  spec.version = UserPattern::VERSION
  spec.authors = ['UserPattern Contributors']
  spec.email = []

  spec.summary = 'Anonymized usage pattern analysis for Rails applications'
  spec.description = 'Track and analyze endpoint usage patterns of logged-in users ' \
                     'with full anonymization. Provides a sortable dashboard with ' \
                     'per-model-type frequency statistics.'
  spec.homepage = 'https://github.com/userpattern/userpattern'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0'

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
