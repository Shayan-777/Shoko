# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Data extraction helpers for download result rows.
          module DownloadBooksScreenComponentDataSupport
            private

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
