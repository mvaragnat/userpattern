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

  describe 'GET /userpatterns' do
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

    it 'ignores a sort parameter when there are no stats' do
      get '/userpatterns', params: { sort: 'total_requests' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('No data collected yet')
    end
  end

  describe 'GET /userpatterns/stylesheet' do
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
