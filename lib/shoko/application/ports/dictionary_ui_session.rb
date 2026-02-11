# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      # Port for dictionary UI lifecycle and interactions.
      module DictionaryUiSession
        def show_panel(result)
          raise NotImplementedError, "#{self.class} must implement #show_panel"
        end

        def show_popup(result)
          raise NotImplementedError, "#{self.class} must implement #show_popup"
        end

        def close
          raise NotImplementedError, "#{self.class} must implement #close"
        end

        def visible?
          raise NotImplementedError, "#{self.class} must implement #visible?"
        end

        def panel_visible?
          raise NotImplementedError, "#{self.class} must implement #panel_visible?"
        end

        def popup_visible?
          raise NotImplementedError, "#{self.class} must implement #popup_visible?"
        end

        def active_result
          raise NotImplementedError, "#{self.class} must implement #active_result"
        end

        def active_kind
          raise NotImplementedError, "#{self.class} must implement #active_kind"
        end

        def insert_char(char)
          raise NotImplementedError, "#{self.class} must implement #insert_char"
        end

        def backspace
          raise NotImplementedError, "#{self.class} must implement #backspace"
        end

        def confirm
          raise NotImplementedError, "#{self.class} must implement #confirm"
        end

        def cancel
          raise NotImplementedError, "#{self.class} must implement #cancel"
        end

        def tab
          raise NotImplementedError, "#{self.class} must implement #tab"
        end

        def swap_languages
          raise NotImplementedError, "#{self.class} must implement #swap_languages"
        end

        def scroll_up
          raise NotImplementedError, "#{self.class} must implement #scroll_up"
        end

        def scroll_down
          raise NotImplementedError, "#{self.class} must implement #scroll_down"
        end

        def setup_mode?
          raise NotImplementedError, "#{self.class} must implement #setup_mode?"
        end

        def fuzzy_mode?
          raise NotImplementedError, "#{self.class} must implement #fuzzy_mode?"
        end

        def toggle_fuzzy(matches = nil)
          raise NotImplementedError, "#{self.class} must implement #toggle_fuzzy"
        end

        def next_entry
          raise NotImplementedError, "#{self.class} must implement #next_entry"
        end

        def prepare_setup_popup
          raise NotImplementedError, "#{self.class} must implement #prepare_setup_popup"
        end

        def show_setup(**kwargs)
          raise NotImplementedError, "#{self.class} must implement #show_setup"
        end

        def update_setup(**kwargs)
          raise NotImplementedError, "#{self.class} must implement #update_setup"
        end
      end
    end
  end
end
