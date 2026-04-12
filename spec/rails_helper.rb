# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'
ENV['DATABASE_URL'] = 'sqlite3::memory:'

require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'userpattern'

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path('dummy', __dir__)
    config.load_defaults 7.0
    config.eager_load = false
    config.secret_key_base = 'test_secret_key_base_for_userpattern_specs_abcdef1234567890'
    config.hosts.clear
    config.action_dispatch.show_exceptions = :none
    config.logger = Logger.new(nil)
    config.active_record.maintain_test_schema = false
  end
end

Dummy::Application.initialize! unless Dummy::Application.initialized?

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.define do
  create_table :userpattern_request_events, force: true do |t|
    t.string   :model_type,           null: false
    t.string   :endpoint,             null: false
    t.string   :anonymous_session_id, null: false
    t.datetime :recorded_at,          null: false
    t.datetime :created_at,           null: false
  end

  create_table :userpattern_violations, force: true do |t|
    t.string   :model_type,      null: false
    t.string   :endpoint,        null: false
    t.string   :period,          null: false
    t.integer  :count,           null: false
    t.integer  :limit,           null: false
    t.string   :user_identifier, null: false
    t.datetime :occurred_at,     null: false
    t.datetime :created_at,      null: false
  end
end

require 'ostruct'
require 'userpattern/buffer'
require 'userpattern/stats_calculator'

class TestController < ActionController::Base
  cattr_accessor :fake_current_user

  def index
    render plain: 'ok'
  end

  private

  def current_user
    self.class.fake_current_user
  end
end

require 'rspec/rails'

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!

  config.before do
    UserPattern.reset!
    UserPattern.configuration.anonymous_salt = 'test_salt_32chars_for_hmac_key!!'
    UserPattern.configuration.flush_interval = 99_999
    TestController.fake_current_user = nil
    UserPattern::RequestEvent.delete_all
    UserPattern::Violation.delete_all
  end

  config.after(:suite) do
    UserPattern.reset!
  end
end
