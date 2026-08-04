# frozen_string_literal: true

require 'shoko/application/ports/outbound/menu_reader_runtime'
require 'shoko/application/ports/outbound/menu_book_selection'
require 'shoko/application/ports/outbound/menu_progress_presenters'
require 'shoko/application/ports/outbound/menu_session_store'
require 'shoko/application/ports/outbound/menu_transient_store'
require 'shoko/core/models/menu_book'
require_relative 'reader_launch_progress_presenter'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Consolidated menu adapter for reader-launch workflow ports.
          class ReaderLaunchPortsAdapter
            include Shoko::Application::Ports::Outbound::MenuReaderRuntime
            include Shoko::Application::Ports::Outbound::MenuBookSelection
            include Shoko::Application::Ports::Outbound::MenuProgressPresenters

            def initialize(menu_state_reader:, browse_screen:, mode_switcher:, menu_session_store:,
                           reader_controller_builder:, menu_transient_store:)
              unless menu_session_store.is_a?(Shoko::Application::Ports::Outbound::MenuSessionStore)
                raise ArgumentError, 'menu_session_store must implement Application::Ports::Outbound::MenuSessionStore'
              end
              unless menu_transient_store.is_a?(Shoko::Application::Ports::Outbound::MenuTransientStore)
                raise ArgumentError, 'menu_transient_store must implement Application::Ports::Outbound::MenuTransientStore'
              end

              @menu_state_reader = menu_state_reader
              @browse_screen = browse_screen
              @mode_switcher = mode_switcher
              @menu_session_store = menu_session_store
              @menu_transient_store = menu_transient_store
              @reader_controller_builder = reader_controller_builder
            end

            def run_reader(path:, preloaded_document:, background_worker:)
              @reader_controller_builder.call(
                path,
                preloaded_document: preloaded_document,
                background_worker: background_worker
              ).run
            end

            def switch_mode(mode)
              @mode_switcher.call(mode)
            end

            def selected_book
              raw = @browse_screen.book_at(selected_index)
              return nil if raw.nil?

              Shoko::Core::Models::MenuBook.from_h(raw)
            end

            def filtered_books
              Array(@browse_screen.filtered_epubs).map do |entry|
                Shoko::Core::Models::MenuBook.from_h(entry)
              end
            end

            def build
              ReaderLaunchProgressPresenter.new(
                @menu_session_store,
                @menu_transient_store
              )
            end

            private

            def selected_index
              (@menu_state_reader.browse_selected || 0).to_i
            end
          end
        end
      end
    end
  end
end
