# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/download_source_policy'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../../../../shared/terminal/text_sanitizer'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/layout'
require_relative '../menu_design/progress_renderer'
require_relative '../menu_design/search_field_renderer'
require_relative '../menu_design/status_renderer'
require_relative '../menu_design/table_renderer'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'
require_relative 'download_books_screen_component/layout_support'
require_relative 'download_books_screen_component/list_renderer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Centralized download screen for Gutendex search + download flow.
          class DownloadBooksScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils
            include DownloadBooksScreenComponentLayoutSupport
            include DownloadBooksScreenComponentListRenderer

            BookItemCtx = Struct.new(:row, :book, :selected, :layout)

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
              frame.render_title(title: 'Download Books')
              frame.render_divider

              render_source(surface, bounds, layout)
              render_search(surface, bounds, layout)
              render_status(surface, bounds, layout)
              render_results(surface, bounds, layout)
              render_footer(surface, bounds, layout, frame: frame)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def results
              menu_state_reader&.download_results || []
            end

            def selected_index
              (menu_state_reader&.download_selected || 0).to_i
            end

            def download_status
              (menu_state_reader&.download_status || :idle).to_sym
            end

            def download_message
              menu_state_reader&.download_message.to_s
            end

            def download_count
              (menu_state_reader&.download_count || 0).to_i
            end

            def download_progress
              (menu_state_reader&.download_progress || 0.0).to_f
            end

            def search_query
              menu_state_reader&.download_query || ''
            end

            def search_cursor
              cursor = menu_state_reader&.download_cursor
              cursor ? cursor.to_i : search_query.length
            end

            def search_active?
              menu_state_reader&.mode == :download_search
            end

            def source_selection_active?
              menu_state_reader&.mode == :download_source_select
            end

            def selected_source_index
              max_index = source_options.length - 1
              (menu_state_reader&.download_source_selected || current_source_index).to_i.clamp(0, max_index)
            end

            def current_source
              Shoko::Shared::DownloadSourcePolicy.normalize(config_reader&.download_source) ||
                Shoko::Shared::DownloadSourcePolicy.default_id
            end

            def current_source_index
              source_options.index(current_source) || 0
            end

            def current_source_label
              Shoko::Shared::DownloadSourcePolicy.label_for(current_source)
            end

            def source_options
              Shoko::Shared::DownloadSourcePolicy.canonical_ids
            end

            def menu_state_reader
              return @menu_state_reader if @menu_state_reader

              @menu_state_reader = @dependencies&.menu_state_reader
            end

            def config_reader
              return @config_reader if @config_reader

              @config_reader = @dependencies&.config_reader
            end

            # Data extraction helpers for download result rows.
            def extract_book_fields(book)
              {
                title: safe_text(value_for(book, :title, 'title', 'Untitled')),
                authors: safe_text(Array(value_for(book, :authors, 'authors', [])).join(', ')),
                languages: safe_text(Array(value_for(book, :languages, 'languages', [])).join(',')),
                meta: result_meta(book),
              }
            end

            def value_for(book, key_sym, key_str, default)
              return default unless book.is_a?(Hash)
              return book[key_sym] if book.key?(key_sym)
              return book[key_str] if book.key?(key_str)

              default
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(text.to_s, preserve_newlines: false, preserve_tabs: false)
            end

            def result_meta(book)
              return safe_text(value_for(book, :extension, 'extension', '').to_s.upcase) if libgen_result?(book)

              value_for(book, :download_count, 'download_count', 0).to_i.to_s
            end

            def libgen_result?(book)
              value_for(book, :source, 'source', current_source) == :libgen
            end
          end
        end
      end
    end
  end
end
