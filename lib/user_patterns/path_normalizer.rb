# frozen_string_literal: true

module UserPatterns
  # Normalizes request paths so that URLs differing only by dynamic segments
  # (numeric IDs, UUIDs) are aggregated into a single endpoint pattern.
  # Also redacts identifiable values from query strings.
  module PathNormalizer
    NUMERIC_ID = /\A\d+\z/
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    HEX_TOKEN = /\A[0-9a-f]{16,}\z/i

    ID_PLACEHOLDER = ':id'
    REDACTED_VALUE = ':xxx'

    class << self
      def normalize(path)
        uri_path, query = path.split('?', 2)
        normalized = normalize_path(uri_path)
        normalized = "#{normalized}?#{normalize_query(query)}" if query
        normalized
      end

      private

      def normalize_path(path)
        return path if path == '/'

        segments = path.split('/')
        segments.map { |seg| dynamic_segment?(seg) ? ID_PLACEHOLDER : seg }.join('/')
      end

      def normalize_query(query)
        query.split('&').map { |pair| redact_pair(pair) }.sort.join('&')
      end

      def redact_pair(pair)
        key, value = pair.split('=', 2)
        return pair unless value

        if dynamic_value?(value)
          "#{key}=#{REDACTED_VALUE}"
        else
          pair
        end
      end

      def dynamic_segment?(segment)
        return false if segment.empty?

        segment.match?(NUMERIC_ID) || segment.match?(UUID) || segment.match?(HEX_TOKEN)
      end

      def dynamic_value?(value)
        return false if value.empty?

        value.match?(NUMERIC_ID) || value.match?(UUID) || value.match?(HEX_TOKEN)
      end
    end
  end
end
