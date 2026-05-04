# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPatterns::FlushEventsJob do
  let(:recorded_at) { Time.current }

  let(:events) do
    [
      { model_type: 'User', endpoint: 'GET /classified/files',
        anonymous_session_id: 'mulder_session_x1', recorded_at: recorded_at },
      { model_type: 'User', endpoint: 'POST /reports/upload',
        anonymous_session_id: 'scully_session_s7', recorded_at: recorded_at }
    ]
  end

  describe '#perform' do
    it 'persists events to the database' do
      expect { described_class.new.perform(events) }
        .to change(UserPatterns::RequestEvent, :count).by(2)
    end

    it 'preserves event attributes' do
      described_class.new.perform(events)

      record = UserPatterns::RequestEvent.find_by(endpoint: 'GET /classified/files')
      expect(record.model_type).to eq('User')
      expect(record.anonymous_session_id).to eq('mulder_session_x1')
    end

    it 'handles string-keyed hashes from job deserialization' do
      string_keyed = events.map { |e| e.transform_keys(&:to_s) }

      expect { described_class.new.perform(string_keyed) }
        .to change(UserPatterns::RequestEvent, :count).by(2)
    end

    it 'stamps all rows with the same created_at' do
      described_class.new.perform(events)

      timestamps = UserPatterns::RequestEvent.pluck(:created_at).uniq
      expect(timestamps.size).to eq(1)
    end
  end
end
