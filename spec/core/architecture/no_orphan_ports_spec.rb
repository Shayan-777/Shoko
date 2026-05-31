# frozen_string_literal: true

require 'spec_helper'

# Every *interface* port — a module that declares its contract through
# `raise NotImplementedError` stubs — must have at least one PRODUCTION
# implementer: a non-spec `lib/` class that `include`s it. A port with no
# production implementer is an orphan (a contract honoured only by test doubles,
# or nothing at all) that silently drifts from reality. See audit ARCH-6.
#
# Scope:
#   * Only interface ports are checked. Value-type ports (snapshots,
#     DisplayLine, TerminalSize — built via `define_snapshot`/`Data`) and static
#     catalog ports (MenuCatalog, MenuStatePartition) carry no NotImplementedError
#     stubs, so they are not matched here; they are constructed/read, never
#     `include`d.
#   * Only the implementer side is enforced. Consumers receive typed
#     collaborators and call them by method (duck-typed at the call site), so a
#     live port need not be referenced by name outside its implementer. Checking
#     for a production `include` is therefore the reliable, false-positive-free
#     signal. (A port that is implemented but never *consumed* is a different,
#     duck-typing-opaque problem this guardrail does not attempt to detect.)
RSpec.describe 'No orphan ports' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:ports_root) { File.join(lib_root, 'application', 'ports') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  def rel(path)
    path.delete_prefix("#{lib_root}/")
  end

  # The port module is the innermost `module X` enclosing the first
  # NotImplementedError stub (derived from the source, not the filename, so it
  # is robust to acronyms and naming drift).
  def interface_port_module_name(content)
    preamble = content.split('NotImplementedError', 2).first
    preamble.to_s.scan(/^\s*module\s+([A-Z]\w+)/).flatten.last
  end

  it 'requires every interface port to have a production implementer (includer)' do
    interface_ports = Dir[File.join(ports_root, '{inbound,outbound}', '**', '*.rb')].select do |path|
      non_comment_content(path).include?('NotImplementedError')
    end
    expect(interface_ports).not_to be_empty, 'No interface ports found — glob or layout changed.'

    production_contents = Dir[File.join(lib_root, '**', '*.rb')]
                          .reject { |path| path.start_with?("#{ports_root}/") }
                          .map { |path| non_comment_content(path) }

    offenders = interface_ports.filter_map do |path|
      name = interface_port_module_name(non_comment_content(path))
      next "#{rel(path)} (could not determine port module name)" if name.nil?

      include_pattern = /\binclude\b[^\n]*(?<![A-Za-z0-9_])#{Regexp.escape(name)}(?![A-Za-z0-9_])/
      next if production_contents.any? { |content| content.match?(include_pattern) }

      "#{rel(path)} (port #{name} has no production `include`r)"
    end

    expect(offenders).to be_empty,
                         "Orphan interface ports — defined but never implemented in production:\n#{offenders.sort.join("\n")}"
  end
end
