# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Path arithmetic over OPF hrefs.
        #
        # These are archive paths, not filesystem paths: they always use '/'
        # regardless of host platform, so they are resolved with String
        # operations rather than ::File, and both the entry reader and the
        # navigation label resolver ask the same questions of them.
        module OPFPathResolution
          module_function

          # @return [String] the directory portion of an archive path, '' at the root
          def dirname(path)
            str = path.to_s
            idx = str.rindex('/')
            idx ? str[0...idx] : ''
          end
        end
      end
    end
  end
end
