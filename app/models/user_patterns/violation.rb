# frozen_string_literal: true

module UserPatterns
  class Violation < ActiveRecord::Base
    self.table_name = 'user_patterns_violations'

    scope :recent, ->(days = 7) { where('occurred_at > ?', days.days.ago) }
  end
end
