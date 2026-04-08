# frozen_string_literal: true

require 'openssl'

module UserPattern
  # Produces a one-way anonymous session identifier that:
  # - Is consistent within a single session/token lifetime (for per-session stats)
  # - Rotates daily via a date-scoped salt (prevents cross-day correlation)
  # - Cannot be reversed to recover user identity or session ID
  class Anonymizer
    DIGEST = 'SHA256'
    TRUNCATE_LENGTH = 16

    def self.anonymize(request)
      raw = session_fingerprint(request)
      daily_salt = "#{UserPattern.configuration.anonymous_salt}:#{Date.current.iso8601}"
      OpenSSL::HMAC.hexdigest(DIGEST, daily_salt, raw)[0, TRUNCATE_LENGTH]
    end

    class << self
      private

      def session_fingerprint(request)
        detection = UserPattern.configuration.session_detection

        case detection
        when :auto, nil then auto_detect(request)
        when :session   then session_based(request)
        when :header    then header_based(request)
        when Proc       then detection.call(request).to_s
        end
      end

      def auto_detect(request)
        if request.headers['Authorization'].present?
          header_based(request)
        elsif request.respond_to?(:session) && request.session.respond_to?(:id) && request.session.id.present?
          session_based(request)
        else
          request.remote_ip.to_s
        end
      end

      def session_based(request)
        request.session.id.to_s
      end

      def header_based(request)
        request.headers['Authorization'].to_s
      end
    end
  end
end
