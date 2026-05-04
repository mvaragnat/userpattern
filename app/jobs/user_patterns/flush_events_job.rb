# frozen_string_literal: true

module UserPatterns
  # Persists a batch of buffered request events to the database.
  # Offloads DB writes from the request cycle to the job backend
  # (Sidekiq, GoodJob, etc.), eliminating connection pool contention.
  class FlushEventsJob < ActiveJob::Base
    queue_as :default

    def perform(events)
      now = Time.current
      rows = events.map { |e| e.symbolize_keys.merge(created_at: now) }
      UserPatterns::RequestEvent.insert_all(rows)
    end
  end
end
