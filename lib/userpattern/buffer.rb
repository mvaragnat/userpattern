# frozen_string_literal: true

require "concurrent"

module UserPattern
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
      flush_async if @queue.size >= UserPattern.configuration.buffer_size
    end

    def flush
      return if @queue.empty?
      return unless @flushing.make_true

      begin
        events = drain_queue
        return if events.empty?

        now = Time.current
        rows = events.map do |e|
          {
            model_type: e[:model_type],
            endpoint: e[:endpoint],
            anonymous_session_id: e[:anonymous_session_id],
            recorded_at: e[:recorded_at],
            created_at: now
          }
        end

        UserPattern::RequestEvent.insert_all(rows)
      rescue => e
        Rails.logger.error("[UserPattern] Flush error: #{e.message}")
      ensure
        @flushing.make_false
      end
    end

    def shutdown
      @timer&.shutdown
      flush
    end

    def size
      @queue.size
    end

    private

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
        execution_interval: UserPattern.configuration.flush_interval
      ) { flush }
      @timer.execute
    end
  end
end
