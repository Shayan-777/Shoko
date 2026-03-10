# frozen_string_literal: true

lib_root = File.expand_path(__dir__)
$LOAD_PATH.unshift(lib_root) unless $LOAD_PATH.include?(lib_root)

require_relative 'shoko/composition/runtime_composition'

Shoko::Composition::RuntimeComposition.boot!
