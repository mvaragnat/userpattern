# frozen_string_literal: true

require 'rails_helper'
require 'userpattern/threshold_exceeded'
require 'userpattern/threshold_cache'

FakeUser = Struct.new(:id) unless defined?(FakeUser)

RSpec.describe 'Controller tracking', type: :request do
  let(:user) { FakeUser.new(1) }

  describe 'collection mode' do
    describe 'when a tracked model is authenticated' do
      before { TestController.fake_current_user = user }

      it 'buffers an event on each request' do
        get '/test_page'

        expect(response).to have_http_status(:ok)
        expect(UserPattern.buffer.size).to eq(1)
      end

      it 'records the correct model_type and endpoint' do
        get '/test_page'
        UserPattern.buffer.flush

        event = UserPattern::RequestEvent.last
        expect(event.model_type).to eq('User')
        expect(event.endpoint).to eq('GET /test_page')
      end

      it 'generates an anonymous session id' do
        get '/test_page'
        UserPattern.buffer.flush

        event = UserPattern::RequestEvent.last
        expect(event.anonymous_session_id).to match(/\A[0-9a-f]{16}\z/)
      end
    end

    describe 'when no model is authenticated' do
      before { TestController.fake_current_user = nil }

      it 'does not buffer any event' do
        get '/test_page'
        expect(UserPattern.buffer.size).to eq(0)
      end
    end

    describe 'when tracking is disabled' do
      before do
        TestController.fake_current_user = user
        UserPattern.configuration.enabled = false
      end

      it 'does not buffer any event' do
        get '/test_page'
        expect(UserPattern.buffer.size).to eq(0)
      end
    end

    describe 'engine-internal requests' do
      before do
        TestController.fake_current_user = user
        UserPattern.configuration.dashboard_auth = -> {}
      end

      it 'does not track dashboard requests' do
        get '/userpatterns'
        expect(UserPattern.buffer.size).to eq(0)
      end
    end
  end

  describe 'alert mode' do
    let(:threshold_cache) { instance_double(UserPattern::ThresholdCache) }
    let(:store) { ActiveSupport::Cache::MemoryStore.new }

    before do
      TestController.fake_current_user = user
      UserPattern.configuration.mode = :alert
      UserPattern.configuration.violation_actions = [:raise]

      require 'userpattern/rate_limiter'
      allow(threshold_cache).to receive(:limits_for).and_return(nil)
      allow(threshold_cache).to receive(:limits_for)
        .with('User', 'GET /test_page')
        .and_return({ per_minute: 2, per_hour: 10, per_day: 50 })

      limiter = UserPattern::RateLimiter.new(store: store, threshold_cache: threshold_cache)
      allow(UserPattern).to receive(:rate_limiter).and_return(limiter)
    end

    it 'allows requests under the threshold' do
      get '/test_page'
      expect(response).to have_http_status(:ok)
    end

    it 'raises ThresholdExceeded when the limit is exceeded' do
      2.times { get '/test_page' }

      expect { get '/test_page' }.to raise_error(UserPattern::ThresholdExceeded)
    end

    it 'still collects events in alert mode' do
      get '/test_page'
      expect(UserPattern.buffer.size).to eq(1)
    end

    context 'with :log and :record actions' do
      before do
        UserPattern.configuration.violation_actions = %i[log record]
      end

      it 'records the violation and does not raise' do
        3.times { get '/test_page' }

        expect(response).to have_http_status(:ok)
        expect(UserPattern::Violation.count).to eq(1)
      end
    end

    context 'with a custom on_threshold_exceeded callback' do
      it 'calls the callback' do
        callback_called = false
        UserPattern.configuration.on_threshold_exceeded = ->(_v) { callback_called = true }
        UserPattern.configuration.violation_actions = [:log]

        3.times { get '/test_page' }

        expect(callback_called).to be true
      end
    end
  end
end
