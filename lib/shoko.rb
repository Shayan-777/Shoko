# frozen_string_literal: true

lib_root = File.expand_path(__dir__)
$LOAD_PATH.unshift(lib_root) unless $LOAD_PATH.include?(lib_root)

require_relative 'shoko/bootstrap/runtime_bootstrap'

Shoko::Bootstrap::RuntimeBootstrap.boot!
