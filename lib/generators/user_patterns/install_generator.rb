# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module UserPatterns
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path('templates', __dir__)

    desc 'Install UserPatterns: creates the initializer and migrations.'

    def copy_initializer
      template 'initializer.rb', 'config/initializers/user_patterns.rb'
    end

    def copy_request_events_migration
      migration_template(
        'create_user_patterns_request_events.rb.erb',
        'db/migrate/create_user_patterns_request_events.rb'
      )
    end

    def copy_violations_migration
      migration_template(
        'create_user_patterns_violations.rb.erb',
        'db/migrate/create_user_patterns_violations.rb'
      )
    end

    def mount_engine
      route 'mount UserPatterns::Engine, at: "/user_patterns"'
    end

    def display_post_install
      say ''
      say 'UserPatterns installed! Next steps:', :green
      say '  1. Run `rails db:migrate`'
      say '  2. Edit config/initializers/user_patterns.rb to configure tracked models'
      say '  3. Set USER_PATTERNS_DASHBOARD_USER and USER_PATTERNS_DASHBOARD_PASSWORD env vars'
      say '  4. Visit /user_patterns to see the dashboard'
      say ''
    end
  end
end
