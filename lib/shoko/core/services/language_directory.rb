# frozen_string_literal: true

module Shoko
  module Core
    module Services
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
        def candidates_for(languages, side:, query:, source_code: nil)
          base = Array(languages).filter_map { |lang| normalize(lang) }
          base = candidates_for_side(base, side: side, source_code: source_code)
          needle = query.to_s.strip.downcase
          return base if needle.empty?

          base.select do |lang|
            lang[:code].downcase.include?(needle) || lang[:name].downcase.include?(needle)
          end
        end

        # Coerce a backend language object or a (symbol-keyed) language hash into a
        # canonical { code:, name: } hash.
        def normalize(lang)
          code, name, targets = language_fields(lang)
          code = code.to_s.strip
          return nil if code.empty?

          display = name.to_s.strip
          { code:, name: display.empty? ? name_for(code) : display, targets: Array(targets).map(&:to_s) }
        end

        def language_fields(lang)
          return hash_language_fields(lang) if lang.is_a?(Hash)

          [lang.code, lang.name, lang.targets]
        end

        def hash_language_fields(lang)
          normalized = lang.transform_keys { |key| key.to_s.to_sym }
          [normalized[:code], normalized[:name], normalized[:targets]]
        end

        def candidates_for_side(languages, side:, source_code:)
          capabilities_known = capabilities_known?(languages)
          return source_candidates(languages, capabilities_known) if side.to_s == 'source'

          source = languages.find { |lang| lang[:code] == source_code.to_s }
          allowed = Array(source&.dig(:targets))
          target_candidates(languages, allowed, capabilities_known)
        end

        def capabilities_known?(languages)
          languages.any? { |lang| lang[:targets].any? }
        end

        def source_candidates(languages, capabilities_known)
          return languages.reject { |lang| lang[:code] == AUTO } unless capabilities_known

          languages.select { |lang| lang[:targets].any? }
        end

        def target_candidates(languages, allowed, capabilities_known)
          return languages.reject { |lang| lang[:code] == AUTO } unless capabilities_known

          languages.select { |lang| lang[:code] != AUTO && allowed.include?(lang[:code]) }
        end
        private_class_method :language_fields,
                             :hash_language_fields,
                             :capabilities_known?,
                             :source_candidates,
                             :target_candidates
      end
    end
  end
end
