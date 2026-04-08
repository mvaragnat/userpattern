# frozen_string_literal: true

module UserPattern
  class RequestEvent < ActiveRecord::Base
    self.table_name = "userpattern_request_events"

    scope :expired, -> {
      where("recorded_at < ?", UserPattern.configuration.retention_period.days.ago)
    }
  end
end
