# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPatterns::RequestEvent do
  def create_event(attrs = {})
    described_class.create!({
      model_type: 'User',
      endpoint: 'GET /test',
      anonymous_session_id: 'abc123',
      recorded_at: Time.current,
      created_at: Time.current
    }.merge(attrs))
  end

  describe '.expired' do
    it 'includes events older than the retention period' do
      old_event = create_event(recorded_at: 31.days.ago, created_at: 31.days.ago)
      expect(described_class.expired).to include(old_event)
    end

    it 'excludes recent events' do
      recent_event = create_event(recorded_at: 1.day.ago, created_at: 1.day.ago)
      expect(described_class.expired).not_to include(recent_event)
    end

    context 'with a shorter retention_period' do
      before { UserPatterns.configuration.retention_period = 7 }

      it 'expires events older than 7 days' do
        stale = create_event(recorded_at: 8.days.ago, created_at: 8.days.ago)
        expect(described_class.expired).to include(stale)
      end

      it 'keeps events within the 7-day window' do
        fresh = create_event(recorded_at: 6.days.ago, created_at: 6.days.ago)
        expect(described_class.expired).not_to include(fresh)
      end

      it 'expires events that would survive the default 30-day period' do
        mid_range = create_event(recorded_at: 15.days.ago, created_at: 15.days.ago)
        expect(described_class.expired).to include(mid_range)
      end
    end

    context 'with a longer retention_period' do
      before { UserPatterns.configuration.retention_period = 90 }

      it 'keeps events that would be expired under the default 30 days' do
        event = create_event(recorded_at: 60.days.ago, created_at: 60.days.ago)
        expect(described_class.expired).not_to include(event)
      end

      it 'expires events older than 90 days' do
        ancient = create_event(recorded_at: 91.days.ago, created_at: 91.days.ago)
        expect(described_class.expired).to include(ancient)
      end
    end
  end
end
