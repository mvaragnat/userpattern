# frozen_string_literal: true

namespace :userpattern do
  desc 'Remove request events older than the configured retention period'
  task cleanup: :environment do
    deleted = UserPattern.cleanup!
    puts "[UserPattern] Cleaned up #{deleted} expired events."
  end
end
