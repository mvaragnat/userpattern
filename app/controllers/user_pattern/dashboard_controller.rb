# frozen_string_literal: true

require 'userpattern/stats_calculator'

module UserPattern
  class DashboardController < ActionController::Base
    before_action :authenticate_dashboard!
    layout false

    def index
      UserPattern.buffer.flush
      load_stats
      apply_sort!
    end

    def violations
      @violations = Violation
                    .recent(params[:days]&.to_i || 7)
                    .order(occurred_at: :desc)
      @violations = @violations.where(model_type: params[:model_type]) if params[:model_type].present?
    end

    def stylesheet
      css_path = UserPattern::Engine.root.join('app', 'assets', 'stylesheets', 'user_pattern', 'dashboard.css')
      expires_in 1.hour, public: true
      render plain: css_path.read, content_type: 'text/css'
    end

    private

    def load_stats
      @stats = UserPattern::StatsCalculator.compute_all
      @model_types = @stats.map { |s| s[:model_type] }.uniq.sort
      @selected_model = params[:model_type].presence || @model_types.first
      @filtered_stats = @stats.select { |s| s[:model_type] == @selected_model }
      @alert_mode = UserPattern.configuration.alert_mode?
      @threshold_limits = load_threshold_limits
    end

    def load_threshold_limits
      return {} unless @alert_mode && UserPattern.threshold_cache

      UserPattern.threshold_cache.all_limits
    end

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
