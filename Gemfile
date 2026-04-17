# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development, :test do
  gem 'parallel', (RUBY_VERSION < '3.3' ? '< 2.0' : '>= 0')
  gem 'rake'
  gem 'rspec-rails'
  gem 'rubocop', require: false
  gem 'rubocop-rspec', require: false
  gem 'simplecov', require: false
  gem 'sqlite3'
end
