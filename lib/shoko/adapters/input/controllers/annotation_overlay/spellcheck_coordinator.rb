# frozen_string_literal: true

require_relative '../dictionary/constants'
require_relative '../support/message_notifier'
require_relative '../support/session_outcome_support'
require_relative '../../../../shared/type_coercion'
require_relative 'spellcheck_coordinator/lookup_resolution'
require_relative 'spellcheck_coordinator/lookup_scope_support'

module Shoko
  module Adapters
    module Input
      module Controllers
        class AnnotationOverlayController
          # Handles annotation-editor spell suggestion lookup and cycling.
          class SpellcheckCoordinator
            include Shoko::Adapters::Input::Controllers::Support::MessageNotifier
            include Shoko::Adapters::Input::Controllers::Support::SessionOutcomeSupport
            include LookupResolution
            include LookupScopeSupport

            SPELL_SUGGESTION_LIMIT = 5
            SPELL_SUGGESTION_FETCH_LIMIT = 15
            BOUNDARY_ERRORS = [ArgumentError, TypeError, RuntimeError].freeze

            def initialize(dictionary_service:, ui_session:, notification_service:, logger:)
              @dictionary_service = dictionary_service
              @ui_session = ui_session
              @notification_service = notification_service
              @logger = logger
            end

            def run
              target = session_payload(@ui_session&.editor_spellcheck_target)
              word = spellcheck_word(target)

              unless word
                show_suggestions(target: nil, suggestions: [])
                set_message('Place the cursor on a word to spell-check', 2)
                return :handled
              end

              unless @dictionary_service&.available?
                show_suggestions(target: target, suggestions: [])
                set_message('Dictionary datasets unavailable for spell suggestions', 3)
                return :handled
              end

              scopes = spell_lookup_scopes
              if scopes.empty?
                show_suggestions(target: target, suggestions: [])
                set_message('No healthy dictionary datasets available for spell suggestions', 3)
                return :handled
              end

              lookup = resolve_spell_lookup(word, target, scopes)
              scope = lookup[:scope]
              suggestions = lookup[:suggestions]
              show_suggestions(
                target: target,
                suggestions: suggestions,
                scope_key: scope[:key],
                scope_label: scope[:label],
                can_cycle: scopes.length > 1
              )

              if suggestions.empty?
                set_message("No #{scope[:label]} suggestions for '#{word}'", 2)
              else
                set_message("Spelling suggestions for '#{word}' (#{scope[:label]})", 2)
              end

              :handled
            rescue *BOUNDARY_ERRORS => e
              @logger&.debug("AnnotationOverlayController.annotation_editor_spellcheck failed: #{e.message}")
              set_message('Spell suggestions unavailable', 2)
              :handled
            end

            private

            def show_suggestions(**kwargs)
              @ui_session&.editor_show_spell_suggestions(**kwargs)
            end

            def spellcheck_word(target)
              return nil unless target.is_a?(Hash)

              word = target.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }[:word]
              normalized = word.to_s.strip
              normalized.empty? ? nil : normalized
            end

            def spell_language_label(language)
              Dictionary::Constants::LANGUAGE_LABELS[language] || language.to_s.upcase
            end
          end
        end
      end
    end
  end
end
