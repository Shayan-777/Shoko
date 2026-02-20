# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Application-facing contract for reading user configuration.
      module ConfigReader
        def page_numbering_mode
          raise NotImplementedError, "#{self.class} must implement #page_numbering_mode"
        end

        def view_mode
          raise NotImplementedError, "#{self.class} must implement #view_mode"
        end

        def line_spacing
          raise NotImplementedError, "#{self.class} must implement #line_spacing"
        end

        def dictionary_source_lang
          raise NotImplementedError, "#{self.class} must implement #dictionary_source_lang"
        end

        def dictionary_target_lang
          raise NotImplementedError, "#{self.class} must implement #dictionary_target_lang"
        end

        def dictionary_path
          raise NotImplementedError, "#{self.class} must implement #dictionary_path"
        end

        def dictionary_backend
          raise NotImplementedError, "#{self.class} must implement #dictionary_backend"
        end

        def show_page_numbers
          raise NotImplementedError, "#{self.class} must implement #show_page_numbers"
        end

        def kitty_images
          raise NotImplementedError, "#{self.class} must implement #kitty_images"
        end

        def theme
          raise NotImplementedError, "#{self.class} must implement #theme"
        end

        def highlight_quotes
          raise NotImplementedError, "#{self.class} must implement #highlight_quotes"
        end

        def highlight_keywords
          raise NotImplementedError, "#{self.class} must implement #highlight_keywords"
        end
      end
    end
  end
end
