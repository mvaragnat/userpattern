# frozen_string_literal: true

module UserPatterns
  # Normalizes request paths so that URLs differing only by dynamic segments
  # (numeric IDs, UUIDs) are aggregated into a single endpoint pattern.
  # Query strings are stripped entirely for anonymization and to group
  # requests into meaningful buckets (e.g. /users?order=name_asc and
  # /users?order=name_desc both become /users).
  module PathNormalizer
    NUMERIC_ID = /\A\d+\z/
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    HEX_TOKEN = /\A[0-9a-f]{16,}\z/i

    ID_PLACEHOLDER = ':id'

    class << self
      # @param path [String] raw request path (may include query string)
      # @return [String] normalized path with query string removed and
      #   dynamic segments replaced by +:id+
      def normalize(path)
        uri_path = path.split('?', 2).first
        normalize_path(uri_path)
      end

      private

      def normalize_path(path)
        return path if path == '/'

        segments = path.split('/')
        segments.map { |seg| dynamic_segment?(seg) ? ID_PLACEHOLDER : seg }.join('/')
      end

      def dynamic_segment?(segment)
        return false if segment.empty?

        segment.match?(NUMERIC_ID) || segment.match?(UUID) || segment.match?(HEX_TOKEN)
      end
    end
  end
end
