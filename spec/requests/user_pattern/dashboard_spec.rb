# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dashboard', type: :request do
  def create_event(attrs = {})
    UserPattern::RequestEvent.create!({
      model_type: 'User',
      endpoint: 'GET /test',
      anonymous_session_id: 'session_a',
      recorded_at: Time.current,
      created_at: Time.current
    }.merge(attrs))
  end

  def create_violation(attrs = {})
    UserPattern::Violation.create!({
      model_type: 'User',
      endpoint: 'GET /api/test',
      period: 'minute',
      count: 9,
      limit: 8,
      user_identifier: 'abc123def456789a',
      occurred_at: Time.current,
      created_at: Time.current
    }.merge(attrs))
  end

  describe 'secure by default' do
    it 'returns 403 when no env vars and no custom auth are set' do
      UserPattern.configuration.dashboard_auth = nil
      get '/userpatterns'

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include('USERPATTERN_DASHBOARD_USER')
    end

    context 'with env vars set' do
      around do |example|
        ENV['USERPATTERN_DASHBOARD_USER'] = 'testadmin'
        ENV['USERPATTERN_DASHBOARD_PASSWORD'] = 'testsecret'
        UserPattern.reset!
        UserPattern.configuration.anonymous_salt = 'test_salt_32chars_for_hmac_key!!'
        UserPattern.configuration.flush_interval = 99_999
        example.run
      ensure
        ENV.delete('USERPATTERN_DASHBOARD_USER')
        ENV.delete('USERPATTERN_DASHBOARD_PASSWORD')
      end

      it 'requires HTTP Basic Auth' do
        get '/userpatterns'
        expect(response).to have_http_status(:unauthorized)
      end

      it 'allows access with correct credentials' do
        credentials = ActionController::HttpAuthentication::Basic.encode_credentials('testadmin', 'testsecret')
        get '/userpatterns', headers: { 'HTTP_AUTHORIZATION' => credentials }
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'GET /userpatterns' do
    before { UserPattern.configuration.dashboard_auth = -> {} }

    it 'renders the empty state when no data exists' do
      get '/userpatterns'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('UserPattern')
      expect(response.body).to include('No data collected yet')
    end

    it 'displays endpoint stats when events exist' do
      create_event(endpoint: 'GET /api/items')

      get '/userpatterns'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('GET /api/items')
    end

    it 'filters stats by model type' do
      create_event(model_type: 'User',  endpoint: 'GET /users')
      create_event(model_type: 'Admin', endpoint: 'GET /admin')

      get '/userpatterns', params: { model_type: 'Admin' }

      expect(response.body).to include('GET /admin')
      expect(response.body).not_to include('GET /users')
    end

    it 'sorts by requested column descending by default' do
      2.times { create_event(endpoint: 'GET /popular') }
      create_event(endpoint: 'GET /rare')

      get '/userpatterns', params: { sort: 'total_requests' }

      body = response.body
      expect(body.index('GET /popular')).to be < body.index('GET /rare')
    end

    it 'sorts ascending when dir=asc' do
      2.times { create_event(endpoint: 'GET /popular') }
      create_event(endpoint: 'GET /rare')

      get '/userpatterns', params: { sort: 'total_requests', dir: 'asc' }

      body = response.body
      expect(body.index('GET /rare')).to be < body.index('GET /popular')
    end

    it 'shows the event count in the footer' do
      3.times { create_event }

      get '/userpatterns'

      expect(response.body).to include('3 events in store')
    end

    it 'shows the mode badge' do
      get '/userpatterns'
      expect(response.body).to include('Collection Mode')
    end

    it 'ignores a sort parameter when there are no stats' do
      get '/userpatterns', params: { sort: 'total_requests' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('No data collected yet')
    end

    context 'when in alert mode with threshold data' do
      before do
        UserPattern.configuration.mode = :alert
        create_event(endpoint: 'GET /api/items')

        require 'userpattern/threshold_cache'
        cache = instance_double(UserPattern::ThresholdCache)
        allow(cache).to receive(:all_limits).and_return(
          { ['User', 'GET /api/items'] => { per_minute: 8, per_hour: 45, per_day: 150 } }
        )
        allow(UserPattern).to receive(:threshold_cache).and_return(cache)
      end

      it 'shows threshold limit columns' do
        get '/userpatterns'

        expect(response.body).to include('Alert Mode')
        expect(response.body).to include('Limit / Min')
      end
    end
  end

  describe 'GET /userpatterns/violations' do
    before { UserPattern.configuration.dashboard_auth = -> {} }

    it 'renders the violations page' do
      get '/userpatterns/violations'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Violations')
    end

    it 'displays recorded violations' do
      create_violation(endpoint: 'GET /api/danger')

      get '/userpatterns/violations'

      expect(response.body).to include('GET /api/danger')
      expect(response.body).to include('minute')
    end

    it 'shows only recent violations by default' do
      create_violation(occurred_at: 10.days.ago)
      create_violation(endpoint: 'GET /recent', occurred_at: 1.day.ago)

      get '/userpatterns/violations'

      expect(response.body).to include('GET /recent')
      expect(response.body).not_to include('GET /api/test')
    end

    it 'filters violations by model type' do
      create_violation(model_type: 'User', endpoint: 'GET /user_action')
      create_violation(model_type: 'Admin', endpoint: 'GET /admin_action')

      get '/userpatterns/violations', params: { model_type: 'Admin' }

      expect(response.body).to include('GET /admin_action')
      expect(response.body).not_to include('GET /user_action')
    end

    it 'accepts a custom days parameter' do
      create_violation(occurred_at: 20.days.ago, endpoint: 'GET /old')
      create_violation(occurred_at: 1.day.ago, endpoint: 'GET /recent')

      get '/userpatterns/violations', params: { days: 30 }

      expect(response.body).to include('GET /old')
      expect(response.body).to include('GET /recent')
    end
  end

  describe 'GET /userpatterns/stylesheet' do
    before { UserPattern.configuration.dashboard_auth = -> {} }

    it 'serves CSS with the correct content type' do
      get '/userpatterns/stylesheet'

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('text/css')
      expect(response.body).to include('font-family')
    end
  end

  describe 'dashboard authentication' do
    before do
      UserPattern.configuration.dashboard_auth = lambda {
        head :unauthorized unless request.headers['X-Test-Auth'] == 'secret'
      }
    end

    it 'blocks unauthenticated access' do
      get '/userpatterns'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows authenticated access' do
      get '/userpatterns', headers: { 'X-Test-Auth' => 'secret' }
      expect(response).to have_http_status(:ok)
    end
  end
end
