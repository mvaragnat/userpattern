# frozen_string_literal: true

UserPattern::Engine.routes.draw do
  get 'stylesheet', to: 'dashboard#stylesheet', as: :stylesheet
  root to: 'dashboard#index'
end
