# frozen_string_literal: true

Rails.application.routes.draw do
  get "/test_page", to: "test#index"
  mount UserPatterns::Engine, at: "/user_patterns"
end
