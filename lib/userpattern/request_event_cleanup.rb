# frozen_string_literal: true

module UserPattern
  module RequestEventCleanup
    def self.run!
      cutoff = UserPattern.configuration.retention_period.days.ago
      UserPattern::RequestEvent.where("recorded_at < ?", cutoff).delete_all
    end
  end
end
