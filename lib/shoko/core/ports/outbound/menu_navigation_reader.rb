# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Focused reader for menu navigation-related fields.
      module MenuNavigationReader
        def selected
          raise NotImplementedError, "#{self.class} must implement #selected"
        end

        def mode
          raise NotImplementedError, "#{self.class} must implement #mode"
        end

        def browse_selected
          raise NotImplementedError, "#{self.class} must implement #browse_selected"
        end

        def settings_selected
          raise NotImplementedError, "#{self.class} must implement #settings_selected"
        end

        def download_selected
          raise NotImplementedError, "#{self.class} must implement #download_selected"
        end

        def dictionary_selected
          raise NotImplementedError, "#{self.class} must implement #dictionary_selected"
        end

        def wipe_cache_cached?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_cached?"
        end

        def wipe_cache_downloads?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_downloads?"
        end

        def wipe_cache_nuke?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_nuke?"
        end

        def wipe_cache_annotations?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_annotations?"
        end

        def wipe_cache_bookmarks?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_bookmarks?"
        end

        def wipe_cache_config?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_config?"
        end

        def wipe_cache_progress?
          raise NotImplementedError, "#{self.class} must implement #wipe_cache_progress?"
        end
      end
    end
  end
end
