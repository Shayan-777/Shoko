# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      # Builds user-facing feedback for cache wipe selections.
      class SettingsServiceWipeCacheMessageBuilder
        CACHED_ONLY_MESSAGE = "All caches wiped. Use 'Find Book' to rescan"
        MESSAGE_MAP = {
          [true, true, true] => "Caches + downloads + data wiped. Use 'Find Book' to rescan",
          [true, true, false] => "Caches + downloads wiped. Use 'Find Book' to rescan",
          [true, false, true] => "Caches + data wiped. Use 'Find Book' to rescan",
          [false, true, true] => "Downloads + data wiped. Use 'Find Book' to rescan",
          [true, false, false] => CACHED_ONLY_MESSAGE,
          [false, true, false] => "Downloads deleted. Use 'Find Book' to rescan",
          [false, false, true] => 'User data wiped.',
          [false, false, false] => 'Nothing selected to wipe',
        }.freeze

        class << self
          def build(plan)
            return "All data wiped. Use 'Find Book' to rescan" if plan.nuke

            MESSAGE_MAP.fetch([plan.cached, plan.downloads, plan.data?])
          end
        end
      end
    end
  end
end
