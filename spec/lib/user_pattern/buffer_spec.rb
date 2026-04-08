# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPattern::Buffer do
  subject(:buffer) { described_class.new }

  let(:event) do
    {
      model_type: 'User',
      endpoint: 'GET /test',
      anonymous_session_id: 'abc123def456',
      recorded_at: Time.current
    }
  end

  after { buffer.shutdown }

  describe '#push' do
    it 'adds events to the queue' do
      buffer.push(event)
      expect(buffer.size).to eq(1)
    end

    it 'accumulates multiple events' do
      3.times { buffer.push(event) }
      expect(buffer.size).to eq(3)
    end
  end

  describe '#flush' do
    it 'writes buffered events to the database' do
      buffer.push(event)
      buffer.flush

      expect(UserPattern::RequestEvent.count).to eq(1)
    end

    it 'clears the queue' do
      buffer.push(event)
      buffer.flush

      expect(buffer.size).to eq(0)
    end

    it 'persists correct attributes' do
      buffer.push(event)
      buffer.flush

      record = UserPattern::RequestEvent.last
      expect(record.model_type).to eq('User')
      expect(record.endpoint).to eq('GET /test')
      expect(record.anonymous_session_id).to eq('abc123def456')
    end

    it 'handles a batch of events' do
      5.times { |i| buffer.push(event.merge(endpoint: "GET /page_#{i}")) }
      buffer.flush

      expect(UserPattern::RequestEvent.count).to eq(5)
    end

    it 'is a no-op when the queue is empty' do
      expect { buffer.flush }.not_to change(UserPattern::RequestEvent, :count)
    end
  end

  describe '#shutdown' do
    it 'flushes remaining events before stopping' do
      buffer.push(event)
      buffer.shutdown

      expect(UserPattern::RequestEvent.count).to eq(1)
    end
  end
end
