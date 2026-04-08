# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module Userpattern
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path('templates', __dir__)

    desc 'Install UserPattern: creates the initializer and migration.'

    def copy_initializer
      template 'initializer.rb', 'config/initializers/userpattern.rb'
    end

    def copy_migration
      migration_template(
        'create_userpattern_request_events.rb.erb',
        'db/migrate/create_userpattern_request_events.rb'
      )
    end

    def mount_engine
      route 'mount UserPattern::Engine, at: "/userpatterns"'
    end

    def display_post_install
      say ''
      say 'UserPattern installed! Next steps:', :green
      say '  1. Run `rails db:migrate`'
      say '  2. Edit config/initializers/userpattern.rb to configure tracked models'
      say '  3. Visit /userpatterns to see the dashboard'
      say ''
    end
  end
end
