# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../../../../shared/terminal/text_sanitizer'
require_relative '../../../../application/ports/inbound/menu_catalog'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/progress_renderer'
require_relative '../menu_design/search_field_renderer'
require_relative '../menu_design/status_renderer'
require_relative '../menu_design/table_renderer'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'
require_relative 'dictionary_settings_screen_component/action_values'
require_relative 'dictionary_settings_screen_component/layout_support'
require_relative 'dictionary_settings_screen_component/list_renderer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Dictionary settings + catalog download screen.
          class DictionarySettingsScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils
            include DictionarySettingsScreenComponentActionValues
            include DictionarySettingsScreenComponentLayoutSupport
            include DictionarySettingsScreenComponentListRenderer

            ActionItem = Data.define(:key, :label, :value, :action)

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
              @config_reader = nil
            end

            def do_render(surface, bounds)
              layout = layout_metrics(bounds)
              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              frame.render_title(title: 'Dictionary')
              frame.render_divider

              render_settings(surface, bounds, layout)
              render_search(surface, bounds, layout)
              render_status(surface, bounds, layout)
              render_results(surface, bounds, layout)
              render_footer(surface, bounds, layout, frame: frame)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def dictionary_results
              menu_state_reader&.dictionary_results || []
            end

            def filtered_results
              query = dictionary_query.downcase
              return dictionary_results if query.empty?

              dictionary_results.select do |item|
                name = item[:name].to_s.downcase
                pair = "#{item[:source]}-#{item[:target]}".downcase
                name.include?(query) || pair.include?(query)
              end
            end

            def selected_index
              (menu_state_reader&.dictionary_selected || 0).to_i
            end

            def dictionary_query
              menu_state_reader&.dictionary_query.to_s
            end

            def dictionary_cursor
              cursor = menu_state_reader&.dictionary_cursor
              cursor ? cursor.to_i : dictionary_query.length
            end

            def dictionary_mode
              (menu_state_reader&.mode || :dictionary).to_sym
            end

            def search_active?
              dictionary_mode == :dictionary_search
            end

            def dictionary_status
              (menu_state_reader&.dictionary_status || :idle).to_sym
            end

            def dictionary_message
              menu_state_reader&.dictionary_message.to_s
            end

            def dictionary_progress
              (menu_state_reader&.dictionary_progress || 0.0).to_f
            end

            def menu_state_reader
              return @menu_state_reader if @menu_state_reader

              @menu_state_reader = @dependencies&.menu_state_reader
            end

            def config_reader
              return @config_reader if @config_reader

              @config_reader = @dependencies&.config_reader
            end
          end
        end
      end
    end
  end
end
