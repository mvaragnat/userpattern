# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPattern::RequestEvent do
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
  end
end
