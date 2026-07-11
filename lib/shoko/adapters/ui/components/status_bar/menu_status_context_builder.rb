# frozen_string_literal: true

require_relative 'status_context'
require_relative 'format_badge'

module Shoko
  module Adapters
    module Ui
      module Components
        module StatusBar
          # Builds the status-bar context for the menu and its sub-views.
          #
          # Each view contributes its own colored badge and title; where a count is
          # cheaply and reliably available (library size, browse position) it is
          # shown as a trailing counter. On the browse view the bar mirrors the
          # *highlighted* book — its real format-color badge and title — so the
          # format colors carry through from the shelf into the reader.
          class MenuStatusContextBuilder
            # Canonical view -> { label:, title: }.
            VIEWS = {
              menu: { label: 'SHOKO', title: 'Library' },
              browse: { label: 'BROWSE', title: 'Browse Library' },
              library: { label: 'LIBRARY', title: 'Library' },
              settings: { label: 'SETTINGS', title: 'Settings' },
              download: { label: 'DOWNLOAD', title: 'Download Books' },
              translator: { label: 'TRANSLATE', title: 'Translator' },
              rss_reader: { label: 'RSS', title: 'RSS Reader' },
              annotations: { label: 'NOTES', title: 'Annotations' },
              dictionary: { label: 'DICTIONARY', title: 'Dictionary' },
              translator_packs: { label: 'TRANSLATOR', title: 'Translator Settings' },
            }.freeze

            # Sub-modes collapse onto their canonical view.
            MODE_ALIASES = {
              search: :browse,
              dictionary_search: :dictionary,
              translator_packs_search: :translator_packs,
              download_search: :download,
              download_source_select: :download,
              translator_source_dropdown: :translator,
              translator_target_dropdown: :translator,
              rss_reader_feed_input: :rss_reader,
              rss_reader_filter: :rss_reader,
              annotation_editor: :annotations,
              annotation_detail: :annotations,
            }.freeze

            # Text-input modes host their input in the bar, exactly like the
            # reader's in-book search: badge names the input, the typed query
            # follows with the steady caret, and a dim placeholder invites the
            # first keystroke.
            INPUT_MODES = {
              search: { label: 'SEARCH', query: :search_query, placeholder: 'type to filter the shelf' },
              download_search: { label: 'SEARCH', query: :download_query, placeholder: 'search the catalog' },
              dictionary_search: { label: 'FILTER', query: :dictionary_query,
                                   placeholder: 'filter the dictionary catalog' },
              translator_packs_search: { label: 'FILTER', query: :translator_packs_query,
                                         placeholder: 'filter the language packs' },
              rss_reader_feed_input: { label: 'ADD FEED', query: :rss_feed_input,
                                       placeholder: 'paste an RSS or Atom feed URL' },
              rss_reader_filter: { label: 'FILTER', query: :rss_filter_query,
                                   placeholder: 'filter by title, author, or feed' },
            }.freeze

            COUNTED_VIEWS = %i[menu library].freeze

            def initialize(menu_state_reader:, library_count:, browse_selection: nil)
              @menu_state_reader = menu_state_reader
              @library_count = library_count
              @browse_selection = browse_selection
            end

            def call
              mode = (@menu_state_reader&.mode || :menu).to_sym
              input = INPUT_MODES[mode]
              return input_context(input) if input

              view_key = canonical_view(mode)
              return browse_context if view_key == :browse

              view = VIEWS[view_key] || VIEWS[:menu]
              StatusContext.build(
                badge: FormatBadge.view_badge(view[:label]),
                title: view[:title],
                trailing: trailing_for(view_key)
              )
            end

            private

            def input_context(input)
              query = @menu_state_reader&.public_send(input[:query]).to_s
              StatusContext.build(
                badge: FormatBadge.view_badge(input[:label]),
                title: query,
                placeholder: input[:placeholder],
                caret: true,
                trailing: ['ENTER apply · ESC cancel']
              )
            end

            def canonical_view(mode)
              key = (mode || :menu).to_sym
              resolved = MODE_ALIASES.fetch(key, key)
              VIEWS.key?(resolved) ? resolved : :menu
            end

            def trailing_for(view_key)
              return [] unless COUNTED_VIEWS.include?(view_key)

              [book_count_label(library_count)]
            end

            def browse_context
              selection = @browse_selection&.call || {}
              book = selection[:book]
              total = selection[:total].to_i

              return browse_book_context(book, selection[:index].to_i, total) if book && !book['path'].to_s.empty?

              StatusContext.build(
                badge: FormatBadge.view_badge('BROWSE'),
                title: VIEWS[:browse][:title],
                trailing: [book_count_label(total.positive? ? total : library_count)]
              )
            end

            def browse_book_context(book, index, total)
              ext = FormatBadge.format_for_path(book['path'])
              StatusContext.build(
                badge: FormatBadge.for_format(ext) || FormatBadge.view_badge('BROWSE'),
                title: book_title(book),
                trailing: [position_label(index, total)]
              )
            end

            def book_title(book)
              title = book['title'].to_s.strip
              return title unless title.empty?

              File.basename(book['path'].to_s)
            end

            def position_label(index, total)
              return '' unless total.positive?

              "#{index.clamp(0, total - 1) + 1} / #{total}"
            end

            def book_count_label(count)
              n = count.to_i
              "#{n} #{n == 1 ? 'book' : 'books'}"
            end

            def library_count
              @library_count&.call.to_i
            end
          end
        end
      end
    end
  end
end
