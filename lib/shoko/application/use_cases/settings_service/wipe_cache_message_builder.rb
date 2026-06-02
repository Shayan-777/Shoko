# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      # Builds user-facing feedback for cache wipe selections.
      class SettingsServiceWipeCacheMessageBuilder
        CACHED_ONLY_MESSAGE = "All caches wiped. Use 'Find Book' to rescan"
        NOTHING_SELECTED_MESSAGE = 'Nothing selected to wipe'
        MESSAGE_MAP = {
          [true, true, true] => "Caches + downloads + data wiped. Use 'Find Book' to rescan",
          [true, true, false] => "Caches + downloads wiped. Use 'Find Book' to rescan",
          [true, false, true] => "Caches + data wiped. Use 'Find Book' to rescan",
          [false, true, true] => "Downloads + data wiped. Use 'Find Book' to rescan",
          [true, false, false] => CACHED_ONLY_MESSAGE,
          [false, true, false] => "Downloads deleted. Use 'Find Book' to rescan",
          [false, false, true] => 'User data wiped.',
          [false, false, false] => NOTHING_SELECTED_MESSAGE,
        }.freeze

        class << self
          def build(plan)
            return nuke_message(plan) if plan.nuke

            with_dictionaries(MESSAGE_MAP.fetch([plan.cached, plan.downloads, plan.data?]), plan)
          end

          private

          # Nuke arms every regenerable category but leaves dictionaries alone unless their own flag is set.
          def nuke_message(plan)
            return "All data + dictionaries wiped. Use 'Find Book' to rescan" if plan.dictionary

            "All data wiped (dictionaries kept). Use 'Find Book' to rescan"
          end

          def with_dictionaries(message, plan)
            return message unless plan.dictionary
            return "Dictionaries deleted. Use 'Find Book' to rescan" if message == NOTHING_SELECTED_MESSAGE

            message.sub(/ (wiped|deleted)/, ' + dictionaries \1')
          end
        end
      end
    end
  end
end
