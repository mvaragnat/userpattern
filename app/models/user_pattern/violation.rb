# frozen_string_literal: true

module UserPattern
  class Violation < ActiveRecord::Base
    self.table_name = 'userpattern_violations'

    scope :recent, ->(days = 7) { where('occurred_at > ?', days.days.ago) }
  end
end
