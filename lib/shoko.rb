# frozen_string_literal: true

lib_root = File.expand_path(__dir__)
$LOAD_PATH.unshift(lib_root) unless $LOAD_PATH.include?(lib_root)

require_relative 'shoko/shared/version'
require_relative 'shoko/shared/errors'
require_relative 'shoko/application/unified_application'
require_relative 'shoko/composition/runtime_composition'
require_relative 'shoko/composition/container_factory'
require_relative 'shoko/adapters/input/cli'

Shoko::Composition::FormatRegistryComposition.register!

if ENV['SHOKO_TEST_MODE'] == '1' || ENV['SHOKO_EAGER_BOOT'] == '1'
  Shoko::Composition::RuntimeComposition.boot!
end
