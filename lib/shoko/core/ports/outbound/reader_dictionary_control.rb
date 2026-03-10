# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Capability port for reader dictionary interaction.
        module ReaderDictionaryControl
          def open_dictionary_lookup
            raise NotImplementedError, "#{self.class} must implement #open_dictionary_lookup"
          end

          def close_dictionary_lookup
            raise NotImplementedError, "#{self.class} must implement #close_dictionary_lookup"
          end

          def append_dictionary_text(text)
            raise NotImplementedError, "#{self.class} must implement #append_dictionary_text"
          end

          def delete_dictionary_character
            raise NotImplementedError, "#{self.class} must implement #delete_dictionary_character"
          end

          def submit_dictionary_lookup
            raise NotImplementedError, "#{self.class} must implement #submit_dictionary_lookup"
          end

          def move_dictionary_selection(delta:)
            raise NotImplementedError, "#{self.class} must implement #move_dictionary_selection"
          end

          def cycle_dictionary_result
            raise NotImplementedError, "#{self.class} must implement #cycle_dictionary_result"
          end

          def cycle_dictionary_pair
            raise NotImplementedError, "#{self.class} must implement #cycle_dictionary_pair"
          end

          def swap_dictionary_languages
            raise NotImplementedError, "#{self.class} must implement #swap_dictionary_languages"
          end

          def toggle_dictionary_fuzzy_matching
            raise NotImplementedError, "#{self.class} must implement #toggle_dictionary_fuzzy_matching"
          end
        end
      end
    end
  end
end
