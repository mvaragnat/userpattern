# frozen_string_literal: true

require 'rails_helper'

FakeUser = Struct.new(:id)

RSpec.describe 'Controller tracking', type: :request do
  let(:user) { FakeUser.new(1) }

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

  describe 'ignored paths' do
    before { TestController.fake_current_user = user }

    context 'with an exact string match' do
      before { UserPattern.configuration.ignored_paths = ['/test_page'] }

      it 'does not buffer any event' do
        get '/test_page'
        expect(UserPattern.buffer.size).to eq(0)
      end
    end

    context 'with a regexp match' do
      before { UserPattern.configuration.ignored_paths = [%r{\A/test}] }

      it 'does not buffer any event' do
        get '/test_page'
        expect(UserPattern.buffer.size).to eq(0)
      end
    end

    context 'when the path does not match any pattern' do
      before { UserPattern.configuration.ignored_paths = ['/other', %r{\A/admin}] }

      it 'buffers an event normally' do
        get '/test_page'
        expect(UserPattern.buffer.size).to eq(1)
      end
    end
  end

  describe 'engine-internal requests' do
    before { TestController.fake_current_user = user }

    it 'does not track dashboard requests' do
      get '/userpatterns'
      expect(UserPattern.buffer.size).to eq(0)
    end
  end

  describe 'when tracked method raises an error' do
    before do
      TestController.fake_current_user = user
      allow_any_instance_of(TestController).to receive(:current_user).and_raise(StandardError, 'auth failure')
    end

    it 'silently ignores the error and buffers no event' do
      get '/test_page'
      expect(UserPattern.buffer.size).to eq(0)
    end
  end

  describe 'when tracked method does not exist on the controller' do
    before do
      UserPattern.configuration.tracked_models = [{ name: 'Admin', current_method: :current_admin }]
    end

    it 'does not buffer any event' do
      get '/test_page'
      expect(UserPattern.buffer.size).to eq(0)
    end
  end

  describe 'ignored paths with non-string/non-regexp pattern' do
    before do
      TestController.fake_current_user = user
      UserPattern.configuration.ignored_paths = [:symbol_pattern]
    end

    it 'does not match the pattern and buffers an event normally' do
      get '/test_page'
      expect(UserPattern.buffer.size).to eq(1)
    end
  end
end
