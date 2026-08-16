# frozen_string_literal: true

# docs-kit synced: v1.0.8

# docs-kit configuration — everything that makes this site look like "locallingo"
# rather than any other docs site. The shared chrome (Shell/Sidebar/ThemeSwitcher/
# Code/Page) comes from the gem; only this config differs per site. The `themes`
# MUST match the @plugin "daisyui" { themes: ... } block in
# app/assets/stylesheets/application.tailwind.css.
Rails.application.config.to_prepare do
  DocsKit.configure do |c|
    c.brand        = "locallingo"
    c.title_suffix = "locallingo"

    # The one-line summary agents read first in /llms.txt (the llmstxt.org
    # blockquote under the H1).
    c.tagline = "AI-assisted i18n translation, drift detection, and quality " \
                "linting on top of i18n-tasks — RubyLLM-powered, config-driven, " \
                "with a subcommand CLI and shipped RuboCop cops."

    c.themes = %w[dark light synthwave retro cyberpunk dracula night nord sunset]

    # The version badge in the sidebar header tracks the documented gem. A lambda
    # (not a String) so it re-reads Locallingo::VERSION on every reload — the
    # locallingo path-gem is required as "locallingo/version" (Gemfile), so only
    # the constant loads; the gem's runtime deps never boot inside the docs app.
    c.version_badge = -> { "v#{Locallingo::VERSION}" }

    # Code blocks: a light base with a dark override, so the highlight stays
    # readable when the switcher lands on a dark daisyUI theme. CSS-only scoping
    # ([data-theme=X]) — no JS, no flash.
    c.code_theme      = "Rouge::Themes::Github"  # light themes
    c.code_theme_dark = "Rouge::Themes::Monokai" # dark themes

    # A link to the source repo + the gem, rendered with shipped brand marks.
    c.topbar_links = [
      { href: "https://github.com/zoolutions/locallingo", label: "GitHub", icon: :github },
      { href: "https://rubygems.org/gems/locallingo", label: "RubyGems", icon: :rubygems }
    ]

    # SEO + social sharing. docs-kit emits the full <head> (description, Open
    # Graph, Twitter Card, canonical, favicon, theme-color) from these knobs.
    c.seo.description  = "AI-assisted i18n translation, source-hash drift " \
                         "detection, and quality linting for Rails, built on " \
                         "i18n-tasks and RubyLLM. Config-driven per app and " \
                         "package, with the lingo CLI and shipped RuboCop cops."
    c.seo.site_url     = "https://locallingo.zoolutions.llc"
    # The social-share card is generated from the landing page, not shipped by the
    # gem — run `bin/rails docs_kit:og` (needs a headless browser), which writes
    # app/assets/images/og/og.png, then set this. Until then, no og:image is
    # emitted (a valid card, no 404).
    c.seo.og_image     = "og/og.png"
    c.seo.og_type      = "website"
    c.seo.twitter_card = "summary_large_image"
    c.seo.twitter_site = "@mhenrixon"
    c.seo.locale       = "en_US"
    c.seo.theme_color  = "#1d232a" # daisyUI dark base-100 (themes.first)
    c.seo.favicon      = "/favicon.svg"

    # The landing page (app/views/landings/show.rb renders DocsUI::Landing) — a
    # marketing hero + feature grid + a registry-grouped doc index, all from these
    # knobs. Wrap a run in **double asterisks** to accent it in the primary color.
    c.landing.eyebrow = "i18n toolkit"
    c.landing.title   = "Translate, validate, and lint your **locales**"
    c.landing.lead    = "locallingo extends i18n-tasks with AI translation, " \
                        "source-hash drift detection, and quality linting — one " \
                        "config, one CLI, for every app and package."
    c.landing.install = { code: 'gem "locallingo", group: :development', filename: "Gemfile", lexer: :ruby }
    c.landing.ctas = [
      { label: "Get started", href: "/docs/overview", style: :primary },
      { label: "GitHub", href: "https://github.com/zoolutions/locallingo", style: :ghost, icon: :github }
    ]
    c.landing.features = [
      { icon: "languages", title: "AI translation",
        body: "Translate missing and changed keys through RubyLLM — OpenAI, " \
              "Anthropic, and more, chosen by config. Only what actually changed." },
      { icon: "git-compare", title: "Drift detection",
        body: "Per-key source hashes mark translations outdated when the English " \
              "text changes, so nothing silently goes stale." },
      { icon: "shield-check", title: "CI validation",
        body: "lingo validate --strict gates missing and outdated keys; " \
              "--strict-all adds duplicate-value and manual-edit checks." },
      { icon: "spell-check", title: "Quality linting",
        body: "Static rules, terminology lists, British-spelling drift, and an " \
              "optional AI review pass — with auto-fix for the fixable." },
      { icon: "boxes", title: "Multi-package",
        body: "One default config plus per-package overrides, so an engine or " \
              "gem can translate to its own locales with its own prompt." },
      { icon: "check-check", title: "RuboCop cops",
        body: "Ships RelativeI18nKey (with autocorrect) and StrftimeInView so " \
              "fully-qualified keys and locale-aware dates are enforced." }
    ]

    # The sidebar nav derives from the registry — one heading → one registry.
    # Each registry's authored pages become NavItems automatically (an unwritten
    # page is skipped, so no dead links); the page `group:` values render as the
    # collapsible sub-groups. This also feeds the AI surfaces (/llms.txt,
    # /llms-full.txt, search, MCP) with zero extra code.
    c.nav_registries = { "Docs" => Doc }
  end
end
