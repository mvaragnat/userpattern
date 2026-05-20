# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPatterns::Buffer do
  subject(:buffer) { described_class.new }

  let(:event) do
    {
      model_type: 'User',
      endpoint: 'GET /basement/archives',
      anonymous_session_id: 'agent_mulder_42',
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
      buffer.shutdown

      expect(UserPatterns::RequestEvent.count).to eq(1)
    end

    it 'clears the queue' do
      buffer.push(event)
      buffer.flush

      expect(buffer.size).to eq(0)
    end

    it 'persists correct attributes' do
      buffer.push(event)
      buffer.flush
      buffer.shutdown

      record = UserPatterns::RequestEvent.last
      expect(record.model_type).to eq('User')
      expect(record.endpoint).to eq('GET /basement/archives')
      expect(record.anonymous_session_id).to eq('agent_mulder_42')
    end

    it 'handles a batch of events' do
      5.times { |i| buffer.push(event.merge(endpoint: "GET /case_#{i}")) }
      buffer.flush
      buffer.shutdown

      expect(UserPatterns::RequestEvent.count).to eq(5)
    end

    it 'is a no-op when the queue is empty' do
      expect { buffer.flush }.not_to change(UserPatterns::RequestEvent, :count)
    end
  end

  describe '#push with buffer size exceeded' do
    it 'triggers flush when buffer size is reached' do
      UserPatterns.configuration.buffer_size = 2
      buf = described_class.new

      2.times { buf.push(event) }
      buf.shutdown

      expect(UserPatterns::RequestEvent.count).to eq(2)
    end
  end

  describe '#flush with persistence error' do
    it 'logs the error and does not raise' do
      allow(UserPatterns::RequestEvent).to receive(:insert_all)
        .and_raise(StandardError, 'db error')
      allow(Rails.logger).to receive(:error)

      buffer.push(event)
      buffer.flush
      buffer.shutdown

      expect(Rails.logger).to have_received(:error).with(/Flush error/)
    end
  end

  describe 'timer-based flush' do
    it 'starts a timer that calls flush periodically' do
      timer_block = nil
      fake_timer = instance_double(Concurrent::TimerTask, execute: nil, shutdown: nil)

      allow(Concurrent::TimerTask).to receive(:new) do |**_opts, &block|
        timer_block = block
        fake_timer
      end

      buf = described_class.new
      buf.push(event)
      timer_block.call
      buf.shutdown

      expect(UserPatterns::RequestEvent.count).to eq(1)
    end

    it 'handles nil timer gracefully on shutdown' do
      buf = described_class.new
      buf.instance_variable_set(:@timer, nil)
      expect { buf.shutdown }.not_to raise_error
    end
  end

  describe '#shutdown' do
    it 'flushes remaining events synchronously' do
      buffer.push(event)
      buffer.shutdown

      expect(UserPatterns::RequestEvent.count).to eq(1)
    end

    it 'persists correct attributes on shutdown' do
      buffer.push(event)
      buffer.shutdown

      record = UserPatterns::RequestEvent.last
      expect(record.model_type).to eq('User')
      expect(record.endpoint).to eq('GET /basement/archives')
      expect(record.anonymous_session_id).to eq('agent_mulder_42')
    end
  end
end
