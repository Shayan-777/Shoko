# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      # Normalized selection set for the cache wipe flow.
      SettingsServiceWipeCachePlan = Data.define(
        :cached,
        :downloads,
        :dictionary,
        :annotations,
        :bookmarks,
        :progress,
        :config_file,
        :nuke
      ) do
        class << self
          def build(cached: nil, downloads: nil, nuke: nil, annotations: nil, bookmarks: nil, progress: nil,
                    config_file: nil)
            normalized = base_flags(
              cached: cached,
              downloads: downloads,
              nuke: nuke,
              annotations: annotations,
              bookmarks: bookmarks,
              progress: progress,
              config_file: config_file
            )
            new(**apply_nuke_flags(normalized))
          end

          private

          def base_flags(cached:, downloads:, nuke:, annotations:, bookmarks:, progress:, config_file:)
            {
              cached: truthy_flag(cached, default: true),
              downloads: truthy_flag(downloads),
              dictionary: false,
              annotations: truthy_flag(annotations),
              bookmarks: truthy_flag(bookmarks),
              progress: truthy_flag(progress),
              config_file: truthy_flag(config_file),
              nuke: truthy_flag(nuke),
            }
          end

          def apply_nuke_flags(flags)
            return flags unless flags[:nuke]

            flags.merge(
              cached: true,
              downloads: true,
              dictionary: true,
              annotations: true,
              bookmarks: true,
              progress: true,
              config_file: true
            )
          end

          def truthy_flag(value, default: false)
            return default if value.nil?

            value != false
          end
        end

        def data?
          annotations || bookmarks || progress || config_file
        end
      end
    end
  end
end
