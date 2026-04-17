# frozen_string_literal: true

namespace :user_patterns do
  desc 'Remove request events older than the configured retention period'
  task cleanup: :environment do
    deleted = UserPatterns.cleanup!
    puts "[UserPatterns] Cleaned up #{deleted} expired events."
  end
end
