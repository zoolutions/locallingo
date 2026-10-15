# frozen_string_literal: true

require_relative "../json_extraction"

module Locallingo
  module Providers
    # Thin wrapper over the `ruby_llm` gem. Every translation and quality-review
    # call goes through here so the rest of the gem never touches a provider SDK
    # directly and stays provider-agnostic.
    #
    # A fresh chat is created per call (`assume_model_exists: true` skips
    # RubyLLM's registry lookup — the configured model id is the source of
    # truth) so independent batches don't share conversation history. The
    # response is parsed with the robust JsonExtraction extractor because not
    # every provider guarantees fenceless JSON.
    #
    # The system prompt is marked as a prompt cache boundary: the translation
    # prompt is built once per locale and reused by every batch, so providers
    # that support caching (Anthropic, OpenAI-compatible) bill the repeated
    # prefix at the cached rate.
    #
    # Every chat runs on a `RubyLLM::Context`: the one given
    # (`RubyLLM.context { |c| c.anthropic_api_key = … }`), else a fresh one built
    # for that chat from the resolved key. The global `RubyLLM.config` is never
    # written, so translators with different keys (one per tenant) can run
    # concurrently.
    class RubyLLM
      # Maps a RubyLLM provider symbol to the ENV var whose presence indicates
      # credentials are available, so we can fail fast with a clear message
      # before making a network call.
      CREDENTIAL_ENV = {
        openai: "OPENAI_API_KEY",
        anthropic: "ANTHROPIC_API_KEY",
        gemini: "GEMINI_API_KEY",
        deepseek: "DEEPSEEK_API_KEY",
        openrouter: "OPENROUTER_API_KEY"
      }.freeze

      attr_reader :provider, :context

      def initialize(provider:, context: nil)
        @provider = provider.to_sym
        @context = context
      end

      # True when a key for the configured provider is found in any source
      # (Locallingo settings, host RubyLLM config, ENV). Unknown providers are
      # assumed configured (RubyLLM may source the key elsewhere) rather than
      # blocking.
      def credentials?
        return true unless CREDENTIAL_ENV.key?(provider)

        !resolved_api_key.nil?
      end

      # Raise a precise error when the provider has no credentials.
      def ensure_credentials!
        return if credentials?

        if context
          raise MissingCredentialsError,
                "No credentials for provider #{provider.inspect}: the given RubyLLM context " \
                "has no #{key_setting}."
        end

        raise MissingCredentialsError,
              "No credentials for provider #{provider.inspect}. " \
              "Set #{CREDENTIAL_ENV[provider]} in ENV, call " \
              "Locallingo.configure { |c| c.#{provider}_api_key = ... }, or add a " \
              ".locallingo.rb setup file at the project root (loaded by the CLI)."
      end

      # Send +instructions+ (system prompt) + +payload+ (user message, JSON) to
      # the model and return the parsed JSON object as a Hash.
      def chat(model:, instructions:, payload:)
        require "ruby_llm"

        conversation = new_chat(model).with_instructions(instructions, cache_until_here: true)
        response = conversation.ask(JSON.pretty_generate(payload))
        JsonExtraction.extract_object(response.content)
      end

      private

      def new_chat(model)
        (context || chat_context).chat(model:, provider:, assume_model_exists: true)
      end

      # A context of its own for one chat. `RubyLLM.context` copies the global
      # config, so a key the host app set via RubyLLM.configure carries over;
      # an explicit `Locallingo.configure` key wins over it (re-resolved every
      # chat so callables stay live), and ENV fills in when neither is set
      # (RubyLLM does not read provider keys from ENV on its own, so a
      # standalone CLI run would otherwise raise "Missing configuration").
      def chat_context
        ::RubyLLM.context do |config|
          setting = key_setting
          next unless CREDENTIAL_ENV.key?(provider) && config.respond_to?("#{setting}=")

          key = settings_api_key
          key ||= env_api_key if presence(config.public_send(setting)).nil?
          config.public_send("#{setting}=", key) unless key.nil?
        end
      end

      # Key resolution across sources, in precedence order. Used by
      # #credentials? as a fail-fast check before any network call.
      def resolved_api_key
        return context_api_key if context

        settings_api_key || host_configured_api_key || env_api_key
      end

      # With a context, its own config is the only source: the chat never
      # reads the settings, the global config or ENV.
      def context_api_key
        config = context.config
        config.respond_to?(key_setting) ? presence(config.public_send(key_setting)) : nil
      end

      def settings_api_key
        Locallingo.settings.api_key_for(provider)
      end

      # A key the host app set via RubyLLM.configure — only inspected when
      # ruby_llm is already loaded (we never require it just to peek).
      def host_configured_api_key
        return nil unless defined?(::RubyLLM)

        config = ::RubyLLM.config
        return nil unless config.respond_to?(key_setting)

        presence(config.public_send(key_setting))
      end

      def env_api_key
        env = CREDENTIAL_ENV[provider]
        env ? presence(ENV.fetch(env, "")) : nil
      end

      def key_setting = "#{provider}_api_key"

      def presence(value)
        key = value.to_s.strip
        key.empty? ? nil : key
      end
    end
  end
end
