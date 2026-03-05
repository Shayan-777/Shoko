# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Sidebar::EntryLineBuilder do
  around do |example|
    Shoko::Adapters::Ui::Constants::Ui.apply_color_mode(:light)
    example.run
  ensure
    Shoko::Adapters::Ui::Constants::Ui.apply_color_mode(:dark)
  end

  it 'uses the active highlight background for selected rows in light mode' do
    entry = Struct.new(:level).new(1)
    component_struct = Struct.new(:prefix, :icon, :entry, :continuation_prefix) do
      def icon_present?
        !icon.to_s.empty?
      end
    end
    components = component_struct.new('', '', entry, '')

    rendered_line = described_class.new(components, ['Chapter 1']).build_selected.first

    expect(rendered_line).to include(Shoko::Adapters::Ui::Constants::Ui::HIGHLIGHT_BG_ACTIVE)
    expect(rendered_line).to include(Shoko::Adapters::Ui::Constants::Ui::COLOR_TEXT_PRIMARY)
    expect(rendered_line).not_to include(Shoko::Shared::Terminal::Ansi::BG_GREY)
  end
end
