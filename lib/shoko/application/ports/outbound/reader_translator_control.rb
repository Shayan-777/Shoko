# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Outbound control port for the in-book translator reader mode. Implemented by
        # the reader adapter; the translator use case drives the card lifecycle, the
        # source-text field, the language pair + picker, and translation execution
        # through it. The query/result/pair/picker state is observable in the reader
        # view-state store; these methods are the operations that still need adapter
        # coordination (surface lifecycle + modal mode, running the translation
        # service, populating the language list) plus the contextual input handling
        # that routes the same keys to either the text field or the open picker.
        module ReaderTranslatorControl
          def open_translator_session(_payload = nil)
            raise NotImplementedError, "#{self.class} must implement #open_translator_session"
          end

          def close_translator_session
            raise NotImplementedError, "#{self.class} must implement #close_translator_session"
          end

          def edit_translator_input(_edit_op)
            raise NotImplementedError, "#{self.class} must implement #edit_translator_input"
          end

          def confirm_translator
            raise NotImplementedError, "#{self.class} must implement #confirm_translator"
          end

          def submit_translator
            raise NotImplementedError, "#{self.class} must implement #submit_translator"
          end

          def move_translator_cursor(_cursor_move)
            raise NotImplementedError, "#{self.class} must implement #move_translator_cursor"
          end

          def cycle_translator_picker
            raise NotImplementedError, "#{self.class} must implement #cycle_translator_picker"
          end

          def open_translator_picker(_side)
            raise NotImplementedError, "#{self.class} must implement #open_translator_picker"
          end

          def paste_translator_source
            raise NotImplementedError, "#{self.class} must implement #paste_translator_source"
          end

          def copy_translator_translation
            raise NotImplementedError, "#{self.class} must implement #copy_translator_translation"
          end

          def swap_translator_languages
            raise NotImplementedError, "#{self.class} must implement #swap_translator_languages"
          end
        end
      end
    end
  end
end
