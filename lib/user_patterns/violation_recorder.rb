# frozen_string_literal: true

require 'openssl'

module UserPatterns
  # Persists threshold violations with an anonymized user identifier.
  # The raw user ID is NEVER stored — only a one-way HMAC hash.
  class ViolationRecorder
    def self.record!(violation)
      Violation.create!(
        model_type: violation.model_type,
        endpoint: violation.endpoint,
        period: violation.period,
        count: violation.count,
        limit: violation.limit,
        user_identifier: anonymize_user_id(violation.user_id, violation.model_type),
        occurred_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.error("[UserPatterns] Violation record error: #{e.message}")
    end

    def self.anonymize_user_id(user_id, model_type)
      salt = UserPatterns.configuration.anonymous_salt
      OpenSSL::HMAC.hexdigest('SHA256', salt, "#{model_type}:#{user_id}")[0, 16]
    end
  end
end
