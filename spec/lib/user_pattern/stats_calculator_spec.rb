# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPattern::StatsCalculator do
  def create_event(attrs = {})
    UserPattern::RequestEvent.create!({
      model_type: 'User',
      endpoint: 'GET /dashboard',
      anonymous_session_id: 'session_a',
      recorded_at: Time.current,
      created_at: Time.current
    }.merge(attrs))
  end

  describe '.compute_all' do
    it 'returns an empty array when no events exist' do
      expect(described_class.compute_all).to eq([])
    end

    it 'computes totals and session count' do
      now = Time.current
      create_event(recorded_at: now - 2.minutes, anonymous_session_id: 's1')
      create_event(recorded_at: now - 1.minute,  anonymous_session_id: 's1')
      create_event(recorded_at: now, anonymous_session_id: 's2')

      stats = described_class.compute_all
      expect(stats.length).to eq(1)

      stat = stats.first
      expect(stat[:total_requests]).to eq(3)
      expect(stat[:total_sessions]).to eq(2)
      expect(stat[:avg_per_session]).to eq(1.5)
    end

    it 'groups by model_type and endpoint' do
      create_event(model_type: 'User',  endpoint: 'GET /a')
      create_event(model_type: 'User',  endpoint: 'GET /b')
      create_event(model_type: 'Admin', endpoint: 'GET /a')

      expect(described_class.compute_all.length).to eq(3)
    end

    it 'computes max_per_minute' do
      base = Time.utc(2026, 1, 1, 12, 0, 0)
      3.times { |i| create_event(recorded_at: base + i.seconds) }
      create_event(recorded_at: base + 2.minutes)

      stat = described_class.compute_all.first
      expect(stat[:max_per_minute]).to eq(3)
    end

    it 'computes max_per_hour' do
      base = Time.utc(2026, 1, 1, 12, 0, 0)
      5.times { |i| create_event(recorded_at: base + (i * 10).minutes) }
      2.times { |i| create_event(recorded_at: base + 1.hour + (i * 10).minutes) }

      stat = described_class.compute_all.first
      expect(stat[:max_per_hour]).to eq(5)
    end

    it 'computes max_per_day' do
      base = Time.utc(2026, 1, 1, 12, 0, 0)
      3.times { create_event(recorded_at: base) }
      2.times { create_event(recorded_at: base + 1.day) }

      stat = described_class.compute_all.first
      expect(stat[:max_per_day]).to eq(3)
    end

    it 'computes avg_per_minute across the observed time span' do
      base = Time.utc(2026, 1, 1, 12, 0, 0)
      create_event(recorded_at: base)
      create_event(recorded_at: base + 5.minutes)

      stat = described_class.compute_all.first
      expect(stat[:avg_per_minute]).to be_a(Float)
      expect(stat[:avg_per_minute]).to be > 0
    end
  end
end
