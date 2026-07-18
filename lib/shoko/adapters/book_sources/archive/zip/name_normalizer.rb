# frozen_string_literal: true

module Shoko
  module Zip
    # Utilities for normalizing entry names
    module NameNormalizer
      module_function

      def normalize(name)
        string_value = ensure_string(name)
        binary_string = string_value.force_encoding(Encoding::BINARY)
        with_forward_slashes = binary_string.tr('\\', '/')
        remove_leading_dot_slash(with_forward_slashes)
      end

      def ensure_string(name)
        name.is_a?(String) ? name.dup : name.to_s
      end

      def remove_leading_dot_slash(path)
        path.sub(%r{^\./}, '')
      end
    end
  end
end
