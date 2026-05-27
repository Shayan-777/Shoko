# frozen_string_literal: true

require 'shoko/core/reading/schema'
require 'shoko/application/state/schema/reader_process'
require 'shoko/application/state/schema/reader_pagination'
require 'shoko/application/state/schema/reader_view'
require 'shoko/application/state/schema/menu_process'
require 'shoko/application/state/schema/menu_transient'
require 'shoko/application/state/schema/config'
require 'shoko/application/state/schema/ui_globals'

module SpecSupport
  # Default-state builders for the layered application state hash, used by
  # specs that need to seed a state-store-shaped hash without booting the
  # full composition root.
  #
  # Replaces the test-side accessors that used to live on the old monolithic
  # session schema module; mirrors what each layer's schema fragment would
  # contribute to the initial state hash.
  module StateFixtures
    module_function

    READER_DEFAULTS = Shoko::Core::Reading::Schema::DEFAULTS
                      .merge(Shoko::Application::State::Schema::ReaderProcess::DEFAULTS)
                      .merge(Shoko::Application::State::Schema::ReaderPagination::DEFAULTS)
                      .merge(
                        Shoko::Application::State::Schema::ReaderView::DEFAULTS
                          .except(*Shoko::Application::State::Schema::ReaderView::LOADING_FIELDS)
                      )
                      .freeze

    MENU_DEFAULTS = Shoko::Application::State::Schema::MenuProcess::DEFAULTS
                    .merge(Shoko::Application::State::Schema::MenuTransient::DEFAULTS)
                    .freeze

    CONFIG_DEFAULTS = Shoko::Application::State::Schema::Config::BASE_DEFAULTS

    UI_DEFAULTS = Shoko::Application::State::Schema::UiGlobals::DEFAULTS

    def reader_state_defaults
      READER_DEFAULTS.dup
    end

    def menu_state_defaults
      MENU_DEFAULTS.dup
    end

    def config_state_defaults(kitty_images: false)
      CONFIG_DEFAULTS.merge(kitty_images: kitty_images)
    end

    def ui_state_defaults
      UI_DEFAULTS.dup
    end
  end
end
