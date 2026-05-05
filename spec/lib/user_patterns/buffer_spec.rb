# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPatterns::Buffer do
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

      record = UserPatterns::RequestEvent.last
      expect(record.model_type).to eq('User')
      expect(record.endpoint).to eq('GET /test')
      expect(record.anonymous_session_id).to eq('abc123def456')
    end

    it 'handles a batch of events' do
      5.times { |i| buffer.push(event.merge(endpoint: "GET /page_#{i}")) }
      buffer.flush

      expect(UserPatterns::RequestEvent.count).to eq(5)
    end

    it 'is a no-op when the queue is empty' do
      expect { buffer.flush }.not_to change(UserPatterns::RequestEvent, :count)
    end
  end

  describe '#push with buffer size exceeded' do
    it 'triggers async flush when buffer size is reached' do
      UserPatterns.configuration.buffer_size = 1
      buf = described_class.new
      buf.push(event)
      buf.shutdown

      expect(UserPatterns::RequestEvent.count).to eq(1)
    end

    it 'does not flush before reaching a custom buffer_size' do
      UserPatterns.configuration.buffer_size = 5
      buf = described_class.new
      4.times { buf.push(event) }

      expect(buf.size).to eq(4)
      expect(UserPatterns::RequestEvent.count).to eq(0)

      buf.shutdown
    end

    it 'triggers flush once the custom buffer_size is reached' do
      UserPatterns.configuration.buffer_size = 3
      buf = described_class.new
      3.times { buf.push(event) }
      buf.shutdown

      expect(UserPatterns::RequestEvent.count).to eq(3)
    end
  end

  describe '#flush concurrent guard' do
    it 'is a no-op when another flush is in progress' do
      buffer.push(event)

      flushing = buffer.instance_variable_get(:@flushing)
      flushing.make_true
      buffer.flush

      expect(UserPatterns::RequestEvent.count).to eq(0)

      flushing.make_false
      buffer.flush
      expect(UserPatterns::RequestEvent.count).to eq(1)
    end
  end

  describe '#flush with persistence error' do
    it 'logs the error and does not raise' do
      allow(UserPatterns::RequestEvent).to receive(:insert_all).and_raise(StandardError, 'db error')
      buffer.push(event)

      expect(Rails.logger).to receive(:error).with(/Flush error/)
      expect { buffer.flush }.not_to raise_error
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

      expect(UserPatterns::RequestEvent.count).to eq(1)
      buf.shutdown
    end

    it 'handles nil timer gracefully on shutdown' do
      buf = described_class.new
      buf.instance_variable_set(:@timer, nil)
      expect { buf.shutdown }.not_to raise_error
    end
  end

  describe 'persist_events with empty drain' do
    it 'is a no-op when drain_queue returns empty' do
      buf = described_class.new
      expect(UserPatterns::RequestEvent).not_to receive(:insert_all)
      buf.send(:persist_events)
    end
  end

  describe '#shutdown' do
    it 'flushes remaining events before stopping' do
      buffer.push(event)
      buffer.shutdown

      expect(UserPatterns::RequestEvent.count).to eq(1)
    end
  end
end
