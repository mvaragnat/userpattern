# frozen_string_literal: true

require 'rails_helper'
require 'user_patterns/threshold_exceeded'
require 'user_patterns/threshold_cache'

FakeUser = Struct.new(:id) unless defined?(FakeUser)

RSpec.describe 'Controller tracking', type: :request do
  let(:user) { FakeUser.new(1) }

  describe 'collection mode' do
    describe 'when a tracked model is authenticated' do
      before { TestController.fake_current_user = user }

      it 'buffers an event on each request' do
        get '/test_page'

        expect(response).to have_http_status(:ok)
        expect(UserPatterns.buffer.size).to eq(1)
      end

      it 'records the correct model_type and endpoint' do
        get '/test_page'
        UserPatterns.buffer.flush

        event = UserPatterns::RequestEvent.last
        expect(event.model_type).to eq('User')
        expect(event.endpoint).to eq('GET /test_page')
      end

      it 'generates an anonymous session id' do
        get '/test_page'
        UserPatterns.buffer.flush

        event = UserPatterns::RequestEvent.last
        expect(event.anonymous_session_id).to match(/\A[0-9a-f]{16}\z/)
      end
    end

    describe 'when no model is authenticated' do
      before { TestController.fake_current_user = nil }

      it 'does not buffer any event' do
        get '/test_page'
        expect(UserPatterns.buffer.size).to eq(0)
      end
    end

    describe 'when tracking is disabled' do
      before do
        TestController.fake_current_user = user
        UserPatterns.configuration.enabled = false
      end

      it 'does not buffer any event' do
        get '/test_page'
        expect(UserPatterns.buffer.size).to eq(0)
      end
    end

    describe 'when tracking is re-enabled after being disabled' do
      before { TestController.fake_current_user = user }

      it 'resumes buffering events' do
        UserPatterns.configuration.enabled = false
        get '/test_page'
        expect(UserPatterns.buffer.size).to eq(0)

        UserPatterns.configuration.enabled = true
        get '/test_page'
        expect(UserPatterns.buffer.size).to eq(1)
      end
    end

    describe 'ignored paths' do
      before { TestController.fake_current_user = user }

      it 'does not buffer when path matches a string pattern' do
        UserPatterns.configuration.ignored_paths = ['/test_page']
        get '/test_page'
        expect(UserPatterns.buffer.size).to eq(0)
      end

      it 'does not buffer when path matches a regexp pattern' do
        UserPatterns.configuration.ignored_paths = [%r{\A/test}]
        get '/test_page'
        expect(UserPatterns.buffer.size).to eq(0)
      end

      it 'buffers normally when path does not match any pattern' do
        UserPatterns.configuration.ignored_paths = ['/other', %r{\A/admin}]
        get '/test_page'
        expect(UserPatterns.buffer.size).to eq(1)
      end
    end

    describe 'engine-internal requests' do
      before do
        TestController.fake_current_user = user
        UserPatterns.configuration.dashboard_auth = -> {}
      end

      it 'does not track dashboard requests' do
        get '/user_patterns'
        expect(UserPatterns.buffer.size).to eq(0)
      end
    end
  end

  describe 'alert mode' do
    let(:threshold_cache) { instance_double(UserPatterns::ThresholdCache) }
    let(:store) { ActiveSupport::Cache::MemoryStore.new }

    before do
      TestController.fake_current_user = user
      UserPatterns.configuration.mode = :alert
      UserPatterns.configuration.violation_actions = [:raise]

      require 'user_patterns/rate_limiter'
      allow(threshold_cache).to receive(:limits_for).and_return(nil)
      allow(threshold_cache).to receive(:limits_for)
        .with('User', 'GET /test_page')
        .and_return({ per_minute: 2, per_hour: 10, per_day: 50 })

      limiter = UserPatterns::RateLimiter.new(store: store, threshold_cache: threshold_cache)
      allow(UserPatterns).to receive(:rate_limiter).and_return(limiter)
    end

    it 'allows requests under the threshold' do
      get '/test_page'
      expect(response).to have_http_status(:ok)
    end

    it 'raises ThresholdExceeded when the limit is exceeded' do
      2.times { get '/test_page' }

      expect { get '/test_page' }.to raise_error(UserPatterns::ThresholdExceeded)
    end

    it 'still collects events in alert mode' do
      get '/test_page'
      expect(UserPatterns.buffer.size).to eq(1)
    end

    context 'with :log and :record actions' do
      before do
        UserPatterns.configuration.violation_actions = %i[log record]
      end

      it 'records the violation and does not raise' do
        3.times { get '/test_page' }

        expect(response).to have_http_status(:ok)
        expect(UserPatterns::Violation.count).to eq(1)
      end
    end

    context 'with a custom on_threshold_exceeded callback' do
      it 'calls the callback' do
        callback_called = false
        UserPatterns.configuration.on_threshold_exceeded = ->(_v) { callback_called = true }
        UserPatterns.configuration.violation_actions = [:log]

        3.times { get '/test_page' }

        expect(callback_called).to be true
      end
    end

    context 'with :logout action' do
      it 'calls the logout method' do
        logout_called = false
        UserPatterns.configuration.violation_actions = [:logout]
        UserPatterns.configuration.logout_method = ->(_controller) { logout_called = true }

        3.times { get '/test_page' }

        expect(logout_called).to be true
      end
    end

    context 'with :logout action but no logout_method' do
      it 'does not raise when logout_method is nil' do
        UserPatterns.configuration.violation_actions = [:logout]
        UserPatterns.configuration.logout_method = nil

        3.times { get '/test_page' }

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when tracking is globally disabled' do
      before { UserPatterns.configuration.enabled = false }

      it 'skips rate limiting entirely' do
        10.times { get '/test_page' }
        expect(response).to have_http_status(:ok)
        expect(UserPatterns.buffer.size).to eq(0)
      end
    end

    context 'when the user is nil for a tracked model' do
      before do
        TestController.fake_current_user = nil
      end

      it 'skips rate limiting for unauthenticated requests' do
        get '/test_page'
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'when tracked method raises an error' do
    before do
      TestController.fake_current_user = user
      TestController.define_method(:current_user) { raise StandardError, 'auth failure' }
    end

    after do
      TestController.define_method(:current_user) { self.class.fake_current_user }
    end

    it 'silently ignores the error and buffers no event' do
      get '/test_page'
      expect(UserPatterns.buffer.size).to eq(0)
    end
  end

  describe 'when tracked method does not exist on the controller' do
    before do
      UserPatterns.configuration.tracked_models = [{ name: 'Admin', current_method: :current_admin }]
    end

    it 'does not buffer any event' do
      get '/test_page'
      expect(UserPatterns.buffer.size).to eq(0)
    end
  end

  describe 'ignored paths with non-string/non-regexp pattern' do
    before do
      TestController.fake_current_user = user
      UserPatterns.configuration.ignored_paths = [:symbol_pattern]
    end

    it 'does not match the pattern and buffers an event normally' do
      get '/test_page'
      expect(UserPatterns.buffer.size).to eq(1)
    end
  end

  describe 'per-model path filtering' do
    let(:admin_user) { FakeUser.new(2) }

    before do
      TestController.fake_current_user = user
      TestController.fake_current_admin_user = admin_user
    end

    context 'with except_paths on User model' do
      before do
        UserPatterns.configuration.tracked_models = [
          { name: 'User', current_method: :current_user, except_paths: [%r{\A/admin}] },
          { name: 'AdminUser', current_method: :current_admin_user }
        ]
      end

      it 'does not record a User event for admin paths' do
        get '/admin_team/care_demands'
        UserPatterns.buffer.flush

        events = UserPatterns::RequestEvent.all
        expect(events.map(&:model_type)).to eq(['AdminUser'])
      end

      it 'still records User events for non-admin paths' do
        get '/test_page'
        UserPatterns.buffer.flush

        model_types = UserPatterns::RequestEvent.pluck(:model_type)
        expect(model_types).to include('User')
        expect(model_types).to include('AdminUser')
      end
    end

    context 'with only_paths on AdminUser model' do
      before do
        UserPatterns.configuration.tracked_models = [
          { name: 'User', current_method: :current_user },
          { name: 'AdminUser', current_method: :current_admin_user, only_paths: [%r{\A/admin}] }
        ]
      end

      it 'records AdminUser events only for matching paths' do
        get '/admin_team/care_demands'
        UserPatterns.buffer.flush

        model_types = UserPatterns::RequestEvent.pluck(:model_type)
        expect(model_types).to include('AdminUser')
        expect(model_types).to include('User')
      end

      it 'does not record AdminUser events for non-matching paths' do
        get '/test_page'
        UserPatterns.buffer.flush

        model_types = UserPatterns::RequestEvent.pluck(:model_type)
        expect(model_types).to eq(['User'])
      end
    end

    context 'with both only_paths and except_paths' do
      before do
        UserPatterns.configuration.tracked_models = [
          { name: 'User', current_method: :current_user, except_paths: [%r{\A/admin}] },
          { name: 'AdminUser', current_method: :current_admin_user, only_paths: [%r{\A/admin}] }
        ]
      end

      it 'cleanly separates admin and user endpoints' do
        get '/admin_team/care_demands'
        get '/test_page'
        UserPatterns.buffer.flush

        admin_events = UserPatterns::RequestEvent.where(model_type: 'AdminUser')
        user_events  = UserPatterns::RequestEvent.where(model_type: 'User')

        expect(admin_events.pluck(:endpoint)).to eq(['GET /admin_team/care_demands'])
        expect(user_events.pluck(:endpoint)).to eq(['GET /test_page'])
      end
    end
  end
end
