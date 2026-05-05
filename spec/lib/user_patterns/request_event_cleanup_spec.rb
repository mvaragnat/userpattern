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

    context 'with retention_period set to 7 days' do
      before { UserPatterns.configuration.retention_period = 7 }

      it 'deletes events older than 7 days' do
        create_event(recorded_at: 10.days.ago, created_at: 10.days.ago)
        create_event(recorded_at: 3.days.ago, created_at: 3.days.ago)

        described_class.run!

        expect(UserPatterns::RequestEvent.count).to eq(1)
        expect(UserPatterns::RequestEvent.last.recorded_at).to be > 7.days.ago
      end

      it 'preserves events that the default 30-day period would also keep' do
        create_event(recorded_at: 5.days.ago, created_at: 5.days.ago)

        described_class.run!

        expect(UserPatterns::RequestEvent.count).to eq(1)
      end
    end

    context 'with retention_period set to 90 days' do
      before { UserPatterns.configuration.retention_period = 90 }

      it 'keeps events from 60 days ago that the default would delete' do
        create_event(recorded_at: 60.days.ago, created_at: 60.days.ago)

        described_class.run!

        expect(UserPatterns::RequestEvent.count).to eq(1)
      end

      it 'deletes events older than 90 days' do
        create_event(recorded_at: 100.days.ago, created_at: 100.days.ago)

        described_class.run!

        expect(UserPatterns::RequestEvent.count).to eq(0)
      end
    end
  end
end
