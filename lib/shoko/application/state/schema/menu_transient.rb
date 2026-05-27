# frozen_string_literal: true

module Shoko
  module Application
    module State
      module Schema
        # Application-owned menu transient-state schema fragment.
        #
        # Owns the non-persisted slice of `state[:menu]`: workflow results
        # (download/dictionary/translator/RSS payloads), live status, progress,
        # and loading mirrors. These are produced by application workflows in
        # response to user intents and are discarded on restart.
        module MenuTransient
          PARTITION = :menu

          FIELDS = %i[
            download_results
            download_count
            download_next
            download_prev
            download_status
            download_message
            download_progress
            dictionary_results
            dictionary_status
            dictionary_message
            dictionary_progress
            translator_output_text
            translator_detected_source_lang
            translator_languages
            translator_status
            translator_message
            translator_selection
            translator_context_menu
            rss_feeds
            rss_articles
            rss_status
            rss_message
            rss_last_synced_at
            annotations_all
            loading_active
            loading_progress
            loading_message
          ].freeze

          DEFAULTS = {
            download_results: [],
            download_count: 0,
            download_next: nil,
            download_prev: nil,
            download_status: :idle,
            download_message: '',
            download_progress: 0.0,
            dictionary_results: [],
            dictionary_status: :idle,
            dictionary_message: '',
            dictionary_progress: 0.0,
            translator_output_text: '',
            translator_detected_source_lang: nil,
            translator_languages: [],
            translator_status: :idle,
            translator_message: 'Type text to translate.',
            translator_selection: nil,
            translator_context_menu: nil,
            rss_feeds: [],
            rss_articles: [],
            rss_status: :empty,
            rss_message: 'Press A to add a feed URL',
            rss_last_synced_at: nil,
            annotations_all: {},
            loading_active: false,
            loading_progress: nil,
            loading_message: nil,
          }.freeze

          module_function

          def contribute(_context = {})
            { PARTITION => DEFAULTS.slice(*FIELDS) }
          end
        end
      end
    end
  end
end
