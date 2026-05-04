# frozen_string_literal: true

require 'concurrent'

module UserPatterns
  # Thread-safe in-memory buffer that batches request events before flushing
  # via Active Job. Per-request overhead is a single mutex-protected array push.
  #
  # Normal path: events queue up → timer or size threshold triggers flush →
  # FlushEventsJob is enqueued → job backend persists the batch.
  #
  # Shutdown path: remaining events are written synchronously so nothing is
  # lost when the process exits.
  class Buffer
    MAX_DRAIN = 1_000

    def initialize
      @queue = []
      @mutex = Mutex.new
      @flushing = Concurrent::AtomicBoolean.new(false)
      start_timer
    end

    # @param event [Hash] a request event hash ready for persistence
    def push(event)
      size = @mutex.synchronize do
        @queue << event
        @queue.size
      end
      flush if size >= UserPatterns.configuration.buffer_size
    end

    def flush
      return unless @flushing.make_true

      events = drain_queue
      enqueue_persist(events) unless events.empty?
    ensure
      @flushing.make_false
    end

    def shutdown
      @timer&.shutdown
      events = drain_queue
      persist_now(events) unless events.empty?
    end

    def size
      @mutex.synchronize { @queue.size }
    end

    private

    def drain_queue
      @mutex.synchronize { @queue.shift(MAX_DRAIN) }
    end

    def enqueue_persist(events)
      UserPatterns::FlushEventsJob.perform_later(events)
    rescue StandardError => e
      Rails.logger.error("[UserPatterns] Enqueue error, falling back to sync: #{e.message}")
      persist_now(events)
    end

    def persist_now(events)
      now = Time.current
      rows = events.map { |e| e.merge(created_at: now) }
      UserPatterns::RequestEvent.insert_all(rows)
    rescue StandardError => e
      Rails.logger.error("[UserPatterns] Flush error: #{e.message}")
    end

    def start_timer
      @timer = Concurrent::TimerTask.new(
        execution_interval: UserPatterns.configuration.flush_interval
      ) { flush }
      @timer.execute
    end
  end
end
