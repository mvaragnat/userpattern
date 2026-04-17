# frozen_string_literal: true

module UserPatterns
  module RequestEventCleanup
    def self.run!
      cutoff = UserPatterns.configuration.retention_period.days.ago
      UserPatterns::RequestEvent.where('recorded_at < ?', cutoff).delete_all
    end
  end
end
