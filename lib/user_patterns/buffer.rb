# frozen_string_literal: true

require 'concurrent'

module UserPatterns
  # Thread-safe in-memory buffer that batches request events before flushing
  # to the database. Minimizes per-request overhead to a single array push.
  class Buffer
    MAX_DRAIN = 1_000

    def initialize
      @queue = Concurrent::Array.new
      @flushing = Concurrent::AtomicBoolean.new(false)
      start_timer
    end

    def push(event)
      @queue << event
      flush_async if @queue.size >= UserPatterns.configuration.buffer_size
    end

    def flush
      return if @queue.empty?
      return unless @flushing.make_true

      persist_events
    ensure
      @flushing.make_false
    end

    def shutdown
      @timer&.shutdown
      flush
    end

    def size
      @queue.size
    end

    private

    def persist_events
      events = drain_queue
      return if events.empty?

      now = Time.current
      rows = events.map { |e| e.merge(created_at: now) }
      UserPatterns::RequestEvent.insert_all(rows)
    rescue StandardError => e
      Rails.logger.error("[UserPatterns] Flush error: #{e.message}")
    end

    def drain_queue
      events = []
      events << @queue.shift until @queue.empty? || events.size >= MAX_DRAIN
      events
    end

    def flush_async
      Thread.new { flush }
    end

    def start_timer
      @timer = Concurrent::TimerTask.new(
        execution_interval: UserPatterns.configuration.flush_interval
      ) { flush }
      @timer.execute
    end
  end
end
