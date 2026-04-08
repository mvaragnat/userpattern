# frozen_string_literal: true

require 'userpattern/stats_calculator'

module UserPattern
  class DashboardController < ActionController::Base
    before_action :authenticate_dashboard!, only: :index
    layout false

    def index
      UserPattern.buffer.flush

      @stats = UserPattern::StatsCalculator.compute_all
      @model_types = @stats.map { |s| s[:model_type] }.uniq.sort
      @selected_model = params[:model_type].presence || @model_types.first
      @filtered_stats = @stats.select { |s| s[:model_type] == @selected_model }

      apply_sort!
    end

    def stylesheet
      css_path = UserPattern::Engine.root.join('app', 'assets', 'stylesheets', 'user_pattern', 'dashboard.css')
      expires_in 1.hour, public: true
      render plain: css_path.read, content_type: 'text/css'
    end

    private

    def authenticate_dashboard!
      auth = UserPattern.configuration.dashboard_auth
      return unless auth.is_a?(Proc)

      instance_exec(&auth)
    end

    def apply_sort!
      sort_key = params[:sort]&.to_sym
      return unless sort_key && @filtered_stats.first&.key?(sort_key)

      @filtered_stats.sort_by! { |s| s[sort_key] || 0 }
      @filtered_stats.reverse! unless params[:dir] == 'asc'
    end
  end
end
