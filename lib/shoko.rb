# frozen_string_literal: true

lib_root = File.expand_path(__dir__)
$LOAD_PATH.unshift(lib_root) unless $LOAD_PATH.include?(lib_root)

require_relative 'shoko/shared/version'
require_relative 'shoko/shared/errors'
require_relative 'shoko/adapters/input/cli'

# The composition graph loads on first reference, not at require time: a
# plain `require 'shoko'` (or `shoko --help`) stays a thin CLI surface,
# while any touch of the container factory, runtime composition, or the
# application entry pulls in the full graph exactly as before. The
# boot-surface guardrail budgets this file's transitive require set.
module Shoko
  # Application layer: entry constant autoloaded; the layer's files load on
  # first reference through the composition graph.
  module Application
    autoload :UnifiedApplication, 'shoko/application/unified_application'
  end

  # Composition layer: the only place that names concrete classes. Autoloaded
  # so a plain require never pays for the wiring graph.
  module Composition
    autoload :ContainerFactory, 'shoko/composition/container_factory'
    autoload :RuntimeComposition, 'shoko/composition/runtime_composition'
    autoload :FormatRegistryComposition, 'shoko/composition/format_registry_composition'
  end
end

Shoko::Composition::RuntimeComposition.boot! if ENV['SHOKO_TEST_MODE'] == '1' || ENV['SHOKO_EAGER_BOOT'] == '1'
