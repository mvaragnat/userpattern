# frozen_string_literal: true

require 'rails_helper'
require 'userpattern/violation_recorder'
require 'userpattern/threshold_exceeded'

RSpec.describe UserPattern::ViolationRecorder do
  let(:violation) do
    UserPattern::ThresholdExceeded.new(
      endpoint: 'GET /api/users',
      user_id: 42,
      model_type: 'User',
      period: 'minute',
      count: 9,
      limit: 8
    )
  end

  describe '.record!' do
    it 'persists a violation to the database' do
      expect do
        described_class.record!(violation)
      end.to change(UserPattern::Violation, :count).by(1)
    end

    it 'stores anonymized user identifier, not the raw ID' do
      described_class.record!(violation)
      record = UserPattern::Violation.last

      expect(record.user_identifier).not_to eq('42')
      expect(record.user_identifier).to match(/\A[0-9a-f]{16}\z/)
    end

    it 'stores violation details' do
      described_class.record!(violation)
      record = UserPattern::Violation.last

      expect(record.model_type).to eq('User')
      expect(record.endpoint).to eq('GET /api/users')
      expect(record.period).to eq('minute')
      expect(record.count).to eq(9)
      expect(record.limit).to eq(8)
    end
  end

  describe '.anonymize_user_id' do
    it 'produces a 16-char hex string' do
      result = described_class.anonymize_user_id(42, 'User')
      expect(result).to match(/\A[0-9a-f]{16}\z/)
    end

    it 'is deterministic for the same input' do
      first = described_class.anonymize_user_id(42, 'User')
      expect(described_class.anonymize_user_id(42, 'User')).to eq(first)
    end

    it 'differs by model type' do
      user_hash = described_class.anonymize_user_id(42, 'User')
      admin_hash = described_class.anonymize_user_id(42, 'Admin')

      expect(user_hash).not_to eq(admin_hash)
    end
  end
end
