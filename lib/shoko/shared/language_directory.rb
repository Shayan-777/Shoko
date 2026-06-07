# frozen_string_literal: true

module Shoko
  module Shared
    # Curated ISO-639-1 code → English name directory for the translator.
    #
    # Two jobs: resolve a friendly display name for a language code (the
    # translation backend returns names too, but this fills gaps and keeps the
    # picker readable), and provide a sensible baseline list of common languages
    # so the language picker stays fully interactive even when the backend is
    # offline (it can't translate then, but you can still browse and pick).
    module LanguageDirectory
      AUTO = 'auto'
      AUTO_NAME = 'Detect language'

      # Codes mirror the set a stock LibreTranslate instance exposes.
      NAMES = {
        'en' => 'English',
        'ar' => 'Arabic',
        'az' => 'Azerbaijani',
        'bg' => 'Bulgarian',
        'bn' => 'Bengali',
        'ca' => 'Catalan',
        'cs' => 'Czech',
        'da' => 'Danish',
        'de' => 'German',
        'el' => 'Greek',
        'eo' => 'Esperanto',
        'es' => 'Spanish',
        'et' => 'Estonian',
        'eu' => 'Basque',
        'fa' => 'Persian',
        'fi' => 'Finnish',
        'fr' => 'French',
        'ga' => 'Irish',
        'gl' => 'Galician',
        'he' => 'Hebrew',
        'hi' => 'Hindi',
        'hu' => 'Hungarian',
        'id' => 'Indonesian',
        'it' => 'Italian',
        'ja' => 'Japanese',
        'ko' => 'Korean',
        'lt' => 'Lithuanian',
        'lv' => 'Latvian',
        'ms' => 'Malay',
        'nb' => 'Norwegian',
        'nl' => 'Dutch',
        'pl' => 'Polish',
        'pt' => 'Portuguese',
        'ro' => 'Romanian',
        'ru' => 'Russian',
        'sk' => 'Slovak',
        'sl' => 'Slovenian',
        'sq' => 'Albanian',
        'sr' => 'Serbian',
        'sv' => 'Swedish',
        'th' => 'Thai',
        'tl' => 'Tagalog',
        'tr' => 'Turkish',
        'uk' => 'Ukrainian',
        'ur' => 'Urdu',
        'vi' => 'Vietnamese',
        'zh' => 'Chinese',
        'zt' => 'Chinese (traditional)',
      }.freeze

      # Baseline ordering for the offline fallback list: the languages people
      # reach for most, then the rest alphabetically by name.
      PREFERRED = %w[en es fr de it pt ru zh ja ko ar].freeze

      module_function

      # Friendly display name for a code (falls back to the upcased code).
      def name_for(code)
        key = code.to_s.strip.downcase
        return AUTO_NAME if key == AUTO || key.empty?

        NAMES[key] || code.to_s.strip.upcase
      end

      # The offline baseline: [{ code:, name: }], preferred languages first.
      def fallback_languages
        preferred = PREFERRED.map { |code| { code: code, name: NAMES[code] } }
        rest = NAMES
               .except(*PREFERRED)
               .map { |code, name| { code: code, name: name } }
               .sort_by { |entry| entry[:name] }
        preferred + rest
      end

      # The picker candidate list for one side, filtered by +query+. The single
      # source of truth shared by the popup renderer and the controller that
      # moves/confirms the selection, so their indices never diverge. The source
      # side leads with the "Detect language" (auto) entry; both sides match the
      # query against either the code or the name (case-insensitive).
      def candidates_for(languages, side:, query:)
        base = Array(languages).filter_map { |lang| normalize(lang) }
        base = [{ code: AUTO, name: AUTO_NAME }] + base if side.to_s == 'source'
        needle = query.to_s.strip.downcase
        return base if needle.empty?

        base.select do |lang|
          lang[:code].downcase.include?(needle) || lang[:name].downcase.include?(needle)
        end
      end

      # Coerce a backend language object or a (symbol-keyed) language hash into a
      # canonical { code:, name: } hash.
      def normalize(lang)
        code, name =
          if lang.is_a?(Hash)
            [lang[:code], lang[:name]]
          elsif lang.respond_to?(:code)
            [lang.code, lang.respond_to?(:name) ? lang.name : nil]
          end
        code = code.to_s.strip
        return nil if code.empty?

        display = name.to_s.strip
        { code: code, name: display.empty? ? name_for(code) : display }
      end
    end
  end
end
