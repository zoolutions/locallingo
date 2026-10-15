# frozen_string_literal: true

module Locallingo
  # Code-level gem settings, configured via `Locallingo.configure`. Distinct
  # from Locallingo::Configuration, which loads the `.locallingo.yml` project
  # file — Settings holds what must never live in YAML: provider credentials.
  #
  #   Locallingo.configure do |config|
  #     config.anthropic_api_key = ENV.fetch("MY_KEY")          # a String…
  #     config.openai_api_key = -> { Vault.read("openai_key") } # …or a callable
  #   end
  #
  # Callables are resolved lazily on every use (never memoized), so keys can
  # come from sources that aren't ready at configure time or that rotate.
  #
  # A String key is stored as a frozen copy, so settings frozen by
  # `Locallingo.configure` are Ractor-shareable; a callable is kept as is.
  class Settings
    PROVIDERS = %i[openai anthropic gemini deepseek openrouter].freeze

    attr_reader(*PROVIDERS.map { |name| :"#{name}_api_key" })

    PROVIDERS.each do |name|
      define_method(:"#{name}_api_key=") do |value|
        value = value.dup.freeze if value.is_a?(String) && !value.frozen?
        instance_variable_set(:"@#{name}_api_key", value)
      end
    end

    # The usable key for +provider+: callables are called, results stripped,
    # and blank or unknown-provider values come back as nil.
    def api_key_for(provider)
      return nil unless PROVIDERS.include?(provider.to_sym)

      value = public_send("#{provider}_api_key")
      value = value.call if value.respond_to?(:call)
      key = value.to_s.strip
      key.empty? ? nil : key
    end
  end
end
