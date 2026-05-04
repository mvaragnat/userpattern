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
    it 'enqueues a FlushEventsJob with buffered events' do
      buffer.push(event)

      expect { buffer.flush }
        .to have_enqueued_job(UserPatterns::FlushEventsJob).with([event])
    end

    it 'clears the queue' do
      buffer.push(event)
      buffer.flush

      expect(buffer.size).to eq(0)
    end

    it 'is a no-op when the queue is empty' do
      expect { buffer.flush }
        .not_to have_enqueued_job(UserPatterns::FlushEventsJob)
    end
  end

  describe '#push with buffer size exceeded' do
    it 'triggers flush when buffer size is reached' do
      UserPatterns.configuration.buffer_size = 2
      buf = described_class.new

      buf.push(event)
      expect { buf.push(event) }
        .to have_enqueued_job(UserPatterns::FlushEventsJob)

      buf.shutdown
    end
  end

  describe '#flush concurrent guard' do
    it 'is a no-op when another flush is in progress' do
      buffer.push(event)

      flushing = buffer.instance_variable_get(:@flushing)
      flushing.make_true
      buffer.flush

      expect(buffer.size).to eq(1)

      flushing.make_false
      buffer.flush
      expect(buffer.size).to eq(0)
    end
  end

  describe '#flush enqueue failure' do
    it 'falls back to synchronous persistence when enqueue fails' do
      allow(UserPatterns::FlushEventsJob).to receive(:perform_later)
        .and_raise(StandardError, 'Redis down')

      buffer.push(event)
      buffer.flush

      expect(UserPatterns::RequestEvent.count).to eq(1)
    end

    it 'logs the enqueue error' do
      allow(UserPatterns::FlushEventsJob).to receive(:perform_later)
        .and_raise(StandardError, 'Redis down')
      allow(Rails.logger).to receive(:error)

      buffer.push(event)
      buffer.flush

      expect(Rails.logger).to have_received(:error).with(/Enqueue error.*Redis down/)
    end
  end

  describe '#flush with sync persistence error' do
    it 'logs the error and does not raise' do
      allow(UserPatterns::FlushEventsJob).to receive(:perform_later)
        .and_raise(StandardError, 'enqueue failed')
      allow(UserPatterns::RequestEvent).to receive(:insert_all)
        .and_raise(StandardError, 'db error')
      allow(Rails.logger).to receive(:error)

      buffer.push(event)

      expect { buffer.flush }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/Enqueue error/).ordered
      expect(Rails.logger).to have_received(:error).with(/Flush error/).ordered
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

      expect(buf.size).to eq(0)
      buf.shutdown
    end

    it 'handles nil timer gracefully on shutdown' do
      buf = described_class.new
      buf.instance_variable_set(:@timer, nil)
      expect { buf.shutdown }.not_to raise_error
    end
  end

  describe '#shutdown' do
    it 'writes remaining events synchronously' do
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
