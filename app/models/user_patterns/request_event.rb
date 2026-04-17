# frozen_string_literal: true

module UserPatterns
  class RequestEvent < ActiveRecord::Base
    self.table_name = 'user_patterns_request_events'

    scope :expired, lambda {
      where('recorded_at < ?', UserPatterns.configuration.retention_period.days.ago)
    }
  end
end
