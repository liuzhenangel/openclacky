# frozen_string_literal: true

require "pastel"
require_relative "../../version"

module Clacky
  module UI2
    module Components
      # WelcomeBanner displays the startup screen with ASCII logo, tagline, tips, and agent info.
      #
      # When a brand_name is configured via BrandConfig, the hardcoded OPENCLACKY
      # ASCII art is replaced by a dynamically generated logo using artii (FIGlet).
      # Falls back to plain text when the terminal is too narrow or artii fails.
      class WelcomeBanner
        LOGO = <<~'LOGO'
           ██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗██╗      █████╗  ██████╗██╗  ██╗██╗   ██╗
          ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║     ██╔══██╗██╔════╝██║ ██╔╝╚██╗ ██╔╝
          ██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║     ██║     ███████║██║     █████╔╝  ╚████╔╝
          ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║     ██║     ██╔══██║██║     ██╔═██╗   ╚██╔╝
          ╚██████╔╝██║     ███████╗██║ ╚████║╚██████╗███████╗██║  ██║╚██████╗██║  ██╗   ██║
           ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝
        LOGO

        TAGLINE = "[>] AI Coding Assistant & Technical Co-founder"

        TIPS = [
          "[*] Ask questions, edit files, or run commands",
          "[*] Be specific for the best results",
          "[*] Create .clackyrules to customize interactions",
          "[*] Type /help for more commands"
        ].freeze

        # Minimum terminal width required for full logo display
        MIN_WIDTH_FOR_LOGO = 90

        # Artii font used for brand name generation
        ARTII_FONT = "big"

        def initialize
          @pastel = Pastel.new
        end

        # Get current theme from ThemeManager
        def theme
          UI2::ThemeManager.current_theme
        end

        # Render only the logo (ASCII art or simple text based on terminal width)
        # @param width [Integer] Terminal width
        # @return [String] Formatted logo only
        def render_logo(width:)
          lines = []
          lines << ""
          lines << logo_content(width)
          lines << ""
          lines.join("\n")
        end

        # Render startup banner
        # @param width [Integer] Terminal width
        # @return [String] Formatted startup banner
        def render_startup(width:)
          lines = []
          lines << ""
          lines << logo_content(width)
          lines << ""
          lines << @pastel.bright_cyan(TAGLINE)
          lines << @pastel.dim("    Version #{Clacky::VERSION}")
          lines << ""
          TIPS.each do |tip|
            lines << @pastel.dim(tip)
          end
          lines << ""
          lines.join("\n")
        end

        # Render agent welcome section
        # @param working_dir [String] Working directory
        # @param mode [String] Permission mode
        # @return [String] Formatted agent welcome section
        def render_agent_welcome(working_dir:, mode:)
          lines = []
          lines << ""
          lines << separator("=")
          lines << @pastel.bright_green("[+] AGENT MODE INITIALIZED")
          lines << separator("=")
          lines << ""
          lines << info_line("Working Directory", working_dir)
          lines << info_line("Permission Mode", mode)
          lines << ""
          lines << theme.format_text("[!] Type 'exit' or 'quit' to terminate session", :thinking)
          lines << separator("-")
          lines << ""
          lines.join("\n")
        end

        # Render full welcome (startup + agent info)
        # @param working_dir [String] Working directory
        # @param mode [String] Permission mode
        # @param width [Integer] Terminal width
        # @return [String] Full welcome content
        def render_full(working_dir:, mode:, width:)
          render_startup(width: width) + render_agent_welcome(
            working_dir: working_dir,
            mode: mode
          )
        end

        private

        # Returns the colourised logo block.
        # - Branded install: dynamically generated artii ASCII art for the brand name
        # - Standard install: hardcoded OPENCLACKY block-letter logo
        # Falls back to plain text when the terminal is too narrow or artii fails.
        private def logo_content(width)
          brand = brand_config
          if brand.branded?
            generate_brand_logo(brand.brand_name, width)
          else
            if width >= MIN_WIDTH_FOR_LOGO
              @pastel.bright_green(LOGO)
            else
              @pastel.bright_green("Welcome, OpenClacky is here")
            end
          end
        end

        # Generate a brand-name ASCII art logo using artii.
        # Falls back gracefully when artii is unavailable or terminal too narrow.
        private def generate_brand_logo(brand_name, width)
          art = artii_render(brand_name)

          if art && art_fits?(art, width)
            @pastel.bright_green(art)
          elsif art
            # Terminal too narrow for full art — centre-clip or use plain fallback
            @pastel.bright_green(brand_name)
          else
            @pastel.bright_green(brand_name)
          end
        end

        # Render text using artii. Returns nil on any failure.
        private def artii_render(text)
          require "artii"
          a = Artii::Base.new(font: ARTII_FONT)
          a.asciify(text)
        rescue LoadError, StandardError
          nil
        end

        # Check whether the ASCII art fits within the terminal width.
        private def art_fits?(art, width)
          art.lines.map { |l| l.chomp.length }.max.to_i <= width
        end

        # Lazily load and cache BrandConfig to avoid circular require issues.
        private def brand_config
          require_relative "../../brand_config"
          Clacky::BrandConfig.load
        rescue LoadError, StandardError
          # Return a neutral stub when brand_config is unavailable
          Object.new.tap { |o| o.define_singleton_method(:branded?) { false } }
        end

        private def info_line(label, value)
          label_text = @pastel.cyan("[#{label}]")
          value_text = theme.format_text(value, :info)
          "    #{label_text} #{value_text}"
        end

        private def separator(char = "-")
          theme.format_text(char * 80, :thinking)
        end
      end
    end
  end
end
