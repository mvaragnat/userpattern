# frozen_string_literal: true

module UserPattern
  class ThresholdExceeded < StandardError
    attr_reader :endpoint, :user_id, :model_type, :period, :count, :limit

    def initialize(endpoint:, user_id:, model_type:, period:, count:, limit:)
      @endpoint = endpoint
      @user_id = user_id
      @model_type = model_type
      @period = period
      @count = count
      @limit = limit
      super(build_message)
    end

    private

    def build_message
      "Rate limit exceeded: #{endpoint} — " \
        "#{count}/#{period} (max: #{limit}) " \
        "by #{model_type}##{user_id}"
    end
  end
end
