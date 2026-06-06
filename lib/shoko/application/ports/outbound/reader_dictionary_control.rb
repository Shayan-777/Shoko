# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Capability port for reader dictionary interaction.
        #
        # The query and the selected-result index are observable reader view-state
        # written by the dictionary use case (the definition popup re-renders from
        # it). The methods below are the operations that still need adapter/service
        # coordination: surface lifecycle (popup create/teardown + modal mode),
        # running the dictionary lookup, and language/fuzzy navigation. Mirrors
        # ReaderSearchControl.
        module ReaderDictionaryControl
          def open_dictionary_lookup(payload = nil)
            raise NotImplementedError, "#{self.class} must implement #open_dictionary_lookup"
          end

          def close_dictionary_lookup
            raise NotImplementedError, "#{self.class} must implement #close_dictionary_lookup"
          end

          def submit_dictionary_lookup
            raise NotImplementedError, "#{self.class} must implement #submit_dictionary_lookup"
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

          # First-run install wizard input. When `dictionary_setup_active` is set,
          # the bar's edit/confirm/move/apply intents drive the centered wizard's
          # language-code field instead of the lookup query.
          def edit_dictionary_setup(edit_op)
            raise NotImplementedError, "#{self.class} must implement #edit_dictionary_setup"
          end

          def confirm_dictionary_setup
            raise NotImplementedError, "#{self.class} must implement #confirm_dictionary_setup"
          end

          def move_dictionary_setup(delta:)
            raise NotImplementedError, "#{self.class} must implement #move_dictionary_setup"
          end

          def apply_dictionary_setup
            raise NotImplementedError, "#{self.class} must implement #apply_dictionary_setup"
          end
        end
      end
    end
  end
end
