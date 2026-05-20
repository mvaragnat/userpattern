# frozen_string_literal: true

require 'concurrent'

module UserPatterns
  # Thread-safe in-memory buffer that batches request events before flushing
  # to the database. Per-request overhead is a single mutex-protected array push.
  #
  # A SingleThreadExecutor serializes all DB writes on a dedicated thread,
  # keeping exactly one connection checked out and zero contention with
  # the web workers' pool.
  #
  # Shutdown path: remaining events are written synchronously so nothing is
  # lost when the process exits.
  class Buffer
    MAX_DRAIN = 1_000

    def initialize
      @queue = []
      @mutex = Mutex.new
      @executor = Concurrent::SingleThreadExecutor.new
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
      events = drain_queue
      return if events.empty?

      @executor.post { persist(events) }
    end

    def shutdown
      @timer&.shutdown
      @executor.shutdown
      @executor.wait_for_termination(5)
      events = drain_queue
      persist(events) unless events.empty?
    end

    def size
      @mutex.synchronize { @queue.size }
    end

    private

    def drain_queue
      @mutex.synchronize { @queue.shift(MAX_DRAIN) }
    end

    def persist(events)
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
