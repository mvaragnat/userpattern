# frozen_string_literal: true

require 'rails_helper'
require 'user_patterns/request_event_cleanup'

RSpec.describe UserPatterns::RequestEventCleanup do
  def create_event(attrs = {})
    UserPatterns::RequestEvent.create!({
      model_type: 'User',
      endpoint: 'GET /test',
      anonymous_session_id: 'abc123',
      recorded_at: Time.current,
      created_at: Time.current
    }.merge(attrs))
  end

  describe '.run!' do
    it 'deletes events older than the configured retention period' do
      create_event(recorded_at: 40.days.ago, created_at: 40.days.ago)
      create_event(recorded_at: 1.day.ago, created_at: 1.day.ago)

      described_class.run!

      expect(UserPatterns::RequestEvent.count).to eq(1)
      expect(UserPatterns::RequestEvent.last.anonymous_session_id).to eq('abc123')
    end

    it 'does not delete events within the retention period' do
      create_event(recorded_at: 29.days.ago, created_at: 29.days.ago)

      described_class.run!

      expect(UserPatterns::RequestEvent.count).to eq(1)
    end
  end
end
