# frozen_string_literal: true

UserPatterns::Engine.routes.draw do
  get 'stylesheet', to: 'dashboard#stylesheet', as: :stylesheet
  get 'violations', to: 'dashboard#violations', as: :violations
  root to: 'dashboard#index'
end
