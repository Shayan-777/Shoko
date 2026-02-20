# frozen_string_literal: true

module Shoko
  module Adapters::Input::Controllers
    module Dictionary
      module Constants
        COMMON_SETUP_LANGS = %w[en de fr es it pt ru zh ja ko ar hi tr pl uk cs nl].freeze

        LANGUAGE_LABELS = {
          'en' => 'English',
          'de' => 'German',
          'fr' => 'French',
          'es' => 'Spanish',
          'it' => 'Italian',
          'pt' => 'Portuguese',
          'ru' => 'Russian',
          'zh' => 'Chinese',
          'ja' => 'Japanese',
          'ko' => 'Korean',
          'ar' => 'Arabic',
          'hi' => 'Hindi',
          'tr' => 'Turkish',
          'pl' => 'Polish',
          'uk' => 'Ukrainian',
          'cs' => 'Czech',
          'nl' => 'Dutch',
        }.freeze

        LANGUAGE_CODE_MAP = {
          'english' => 'en',
          'eng' => 'en',
          'german' => 'de',
          'deutsch' => 'de',
          'deu' => 'de',
          'ger' => 'de',
          'french' => 'fr',
          'fra' => 'fr',
          'fre' => 'fr',
          'spanish' => 'es',
          'espanol' => 'es',
          'spa' => 'es',
          'italian' => 'it',
          'ita' => 'it',
          'portuguese' => 'pt',
          'por' => 'pt',
          'dutch' => 'nl',
          'nld' => 'nl',
          'dut' => 'nl',
          'polish' => 'pl',
          'pol' => 'pl',
          'czech' => 'cs',
          'cze' => 'cs',
          'ces' => 'cs',
          'ukrainian' => 'uk',
          'ukr' => 'uk',
          'turkish' => 'tr',
          'tur' => 'tr',
          'arabic' => 'ar',
          'ara' => 'ar',
          'hindi' => 'hi',
          'hin' => 'hi',
          'japanese' => 'ja',
          'jpn' => 'ja',
          'korean' => 'ko',
          'kor' => 'ko',
          'rus' => 'ru',
          'russian' => 'ru',
          'zho' => 'zh',
          'chi' => 'zh',
          'chinese' => 'zh',
          'mandarin' => 'zh',
        }.freeze
      end
    end
  end
end
