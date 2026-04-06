# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::TranslationPopupComponent do
  def strip_ansi(text)
    text.to_s.gsub(%r{\e\[[0-9;]*[ -/]*[@-~]}, '')
  end

  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 120, height: 40) }

  subject(:component) { described_class.new }

  before do
    terminal.reset!
  end

  it 'tracks visibility and result state' do
    result = Shoko::Core::Models::TranslationResult.new(
      query: 'Hallo Welt',
      translated_text: 'Hello world',
      source_lang: 'auto',
      target_lang: 'en',
      detected_source_lang: 'de'
    )

    component.show(result)
    expect(component).to be_visible
    expect(component.result.translated_text).to eq('Hello world')

    component.hide
    expect(component).not_to be_visible
    expect(component.result).to be_nil
  end

  it 'renders original and translated text' do
    component.show(
      Shoko::Core::Models::TranslationResult.new(
        query: 'Hallo Welt',
        translated_text: 'Hello world',
        source_lang: 'auto',
        target_lang: 'en',
        detected_source_lang: 'de'
      )
    )

    component.render(surface, bounds)
    rendered = strip_ansi(terminal.writes.map { |write| write[:text] }.join("\n"))

    expect(rendered).to include('Translation')
    expect(rendered).to include('Original')
    expect(rendered).to include('Hallo Welt')
    expect(rendered).to include('Translated')
    expect(rendered).to include('Hello world')
  end

  it 'supports scrolling for long translations' do
    component.show(
      Shoko::Core::Models::TranslationResult.new(
        query: 'Hallo',
        translated_text: Array.new(80, 'translated').join(' '),
        source_lang: 'auto',
        target_lang: 'en',
        detected_source_lang: 'de'
      )
    )
    component.render(surface, bounds)

    expect { component.scroll_down }.to change(component, :scroll_offset).by(1)
  end

  it 'caches content lines until theme or result changes' do
    first_result = Shoko::Core::Models::TranslationResult.new(
      query: 'Hallo Welt',
      translated_text: 'Hello world',
      source_lang: 'auto',
      target_lang: 'en',
      detected_source_lang: 'de'
    )
    second_result = Shoko::Core::Models::TranslationResult.new(
      query: 'Tschuss',
      translated_text: 'Bye',
      source_lang: 'auto',
      target_lang: 'en',
      detected_source_lang: 'de'
    )
    allow(component).to receive(:wrap_text).and_call_original

    component.show(first_result)
    component.render(surface, bounds)
    component.render(surface, bounds)

    expect(component).to have_received(:wrap_text).twice

    component.update_color_mode(:light)
    component.render(surface, bounds)
    expect(component).to have_received(:wrap_text).exactly(4).times

    component.hide
    component.show(second_result)
    component.render(surface, bounds)
    expect(component).to have_received(:wrap_text).exactly(6).times
  end

  it 'renders using the centralized light-mode palette' do
    component.update_color_mode(:light)
    component.show(
      Shoko::Core::Models::TranslationResult.new(
        query: 'Hallo Welt',
        translated_text: 'Hello world',
        source_lang: 'auto',
        target_lang: 'en',
        detected_source_lang: 'de'
      )
    )

    component.render(surface, bounds)

    palette = Shoko::Adapters::Ui::Constants::ComponentPalettes.fetch(:translation_popup, :light)
    rendered = terminal.writes.map { |write| write[:text] }.join("\n")

    expect(rendered).to include(palette[:panel_bg])
    expect(rendered).to include(palette[:header_fg])
    expect(rendered).to include(palette[:body_fg])
  end
end
