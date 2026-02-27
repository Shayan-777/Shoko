# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_navigation_reader'
require_relative '../../../core/ports/outbound/menu_query_reader'
require_relative '../../../core/ports/outbound/menu_data_reader'
require_relative 'selectors/menu_selectors'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Application adapter implementing the MenuStateReader port.
        # Reads menu state from application state using MenuSelectors.
        class MenuStateReaderAdapter
          include Core::Ports::Outbound::MenuNavigationReader
          include Core::Ports::Outbound::MenuQueryReader
          include Core::Ports::Outbound::MenuDataReader

          def initialize(state)
            @state = state
          end

          # @return [Integer, nil]
          def selected
            Selectors::MenuSelectors.selected(@state)
          end

          # @return [Symbol, nil]
          def mode
            Selectors::MenuSelectors.mode(@state)
          end

          # @return [Integer, nil]
          def browse_selected
            Selectors::MenuSelectors.browse_selected(@state)
          end

          # @return [String]
          def search_query
            Selectors::MenuSelectors.search_query(@state)
          end

          # @return [Integer, nil]
          def search_cursor
            Selectors::MenuSelectors.search_cursor(@state)
          end

          # @return [Boolean]
          def search_active?
            Selectors::MenuSelectors.search_active?(@state)
          end

          # @return [Integer, nil]
          def settings_selected
            @state.get(%i[menu settings_selected])
          end

          def wipe_cache_cached?
            value = @state.get(%i[menu wipe_cache_cached])
            value.nil? || !!value
          end

          def wipe_cache_downloads?
            !!@state.get(%i[menu wipe_cache_downloads])
          end

          def wipe_cache_nuke?
            !!@state.get(%i[menu wipe_cache_nuke])
          end

          def wipe_cache_annotations?
            !!@state.get(%i[menu wipe_cache_annotations])
          end

          def wipe_cache_bookmarks?
            !!@state.get(%i[menu wipe_cache_bookmarks])
          end

          def wipe_cache_config?
            !!@state.get(%i[menu wipe_cache_config])
          end

          def wipe_cache_progress?
            !!@state.get(%i[menu wipe_cache_progress])
          end

          # @return [String]
          def download_query
            Selectors::MenuSelectors.download_query(@state)
          end

          # @return [Integer, nil]
          def download_cursor
            Selectors::MenuSelectors.download_cursor(@state)
          end

          # @return [Integer, nil]
          def download_selected
            Selectors::MenuSelectors.download_selected(@state)
          end

          # @return [Symbol, nil]
          def download_status
            Selectors::MenuSelectors.download_status(@state)
          end

          # @return [Float, nil]
          def download_progress
            Selectors::MenuSelectors.download_progress(@state)
          end

          # @return [String]
          def dictionary_query
            Selectors::MenuSelectors.dictionary_query(@state)
          end

          # @return [Integer, nil]
          def dictionary_cursor
            Selectors::MenuSelectors.dictionary_cursor(@state)
          end

          # @return [Integer, nil]
          def dictionary_selected
            Selectors::MenuSelectors.dictionary_selected(@state)
          end

          # @return [Symbol, nil]
          def dictionary_status
            Selectors::MenuSelectors.dictionary_status(@state)
          end

          # @return [Float, nil]
          def dictionary_progress
            Selectors::MenuSelectors.dictionary_progress(@state)
          end

          # @return [Hash]
          def annotations_all
            @state.get(%i[menu annotations_all]) || {}
          end

          # @return [Hash, nil]
          def selected_annotation
            @state.get(%i[menu selected_annotation])
          end

          # @return [String, nil]
          def selected_annotation_book
            @state.get(%i[menu selected_annotation_book])
          end

          # @return [String]
          def annotation_edit_text
            @state.get(%i[menu annotation_edit_text]) || ''
          end

          # @return [Integer, nil]
          def annotation_edit_cursor
            @state.get(%i[menu annotation_edit_cursor])
          end

          # @return [String, nil]
          def loading_path
            @state.get(%i[menu loading_path])
          end

          # @return [Boolean]
          def loading_active?
            !!@state.get(%i[menu loading_active])
          end

          # @return [Float, nil]
          def loading_progress
            @state.get(%i[menu loading_progress])
          end

          # @return [String, nil]
          def loading_message
            @state.get(%i[menu loading_message])
          end

          # @return [String, nil]
          def download_next
            @state.get(%i[menu download_next])
          end

          # @return [String, nil]
          def download_prev
            @state.get(%i[menu download_prev])
          end

          # @return [Array]
          def download_results
            Array(@state.get(%i[menu download_results]))
          end

          # @return [String, nil]
          def download_message
            @state.get(%i[menu download_message])
          end

          # @return [Integer]
          def download_count
            (@state.get(%i[menu download_count]) || 0).to_i
          end

          # @return [Array]
          def dictionary_results
            Array(@state.get(%i[menu dictionary_results]))
          end

          # @return [String, nil]
          def dictionary_message
            @state.get(%i[menu dictionary_message])
          end
        end
      end
    end
  end
end
