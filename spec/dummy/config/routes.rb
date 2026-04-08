# frozen_string_literal: true

Rails.application.routes.draw do
  get "/test_page", to: "test#index"
  mount UserPattern::Engine, at: "/userpatterns"
end
