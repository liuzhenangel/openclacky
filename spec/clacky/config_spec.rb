# frozen_string_literal: true

RSpec.describe Clacky::Config do
  describe ".load" do
    context "when config file doesn't exist" do
      it "returns a new config with nil values" do
        with_temp_config do |config_file|
          FileUtils.rm_f(config_file) # Ensure it doesn't exist

          config = described_class.load(config_file)
          expect(config.api_key).to be_nil
          expect(config.model).to be_nil
          expect(config.base_url).to be_nil
          expect(config.config_source).to be_nil
        end
      end
    end

    context "when config file exists" do
      it "loads configuration from file" do
        with_temp_config({
          "api_key" => "test-key",
          "model" => "gpt-4",
          "base_url" => "https://api.test.com"
        }) do |config_file|
          config = described_class.load(config_file)

          expect(config.api_key).to eq("test-key")
          expect(config.model).to eq("gpt-4")
          expect(config.base_url).to eq("https://api.test.com")
        end
      end
    end
  end

  describe "#save" do
    it "saves configuration to file" do
      with_temp_config do |config_file|
        config = described_class.new("api_key" => "my-api-key")
        config.save(config_file)

        expect(File).to exist(config_file)
        saved_data = YAML.load_file(config_file)
        expect(saved_data["api_key"]).to eq("my-api-key")
      end
    end

    it "creates config directory if it doesn't exist" do
      Dir.mktmpdir do |dir|
        config_file = File.join(dir, "nested", "config.yml")

        config = described_class.new("api_key" => "test-key")
        config.save(config_file)

        expect(Dir).to exist(File.dirname(config_file))
      end
    end

    it "sets secure file permissions" do
      with_temp_config do |config_file|
        config = described_class.new("api_key" => "secure-key")
        config.save(config_file)

        file_stat = File.stat(config_file)
        permissions = file_stat.mode.to_s(8)[-3..]
        expect(permissions).to eq("600")
      end
    end
  end

  describe "#to_yaml" do
    it "converts config to YAML format" do
      config = described_class.new({
        "api_key" => "test-key",
        "model" => "gpt-4",
        "base_url" => "https://api.test.com"
      })
      yaml = config.to_yaml

      expect(yaml).to include("api_key: test-key")
      expect(yaml).to include("model: gpt-4")
      expect(yaml).to include("base_url: https://api.test.com")
    end
  end

  describe "#config_source" do
    context "when loaded from config file" do
      it "returns 'file'" do
        with_temp_config({"api_key" => "test-key"}) do |config_file|
          config = described_class.load(config_file)
          expect(config.config_source).to eq("file")
        end
      end
    end

    context "when config file doesn't exist" do
      it "returns nil" do
        with_temp_config do |config_file|
          FileUtils.rm_f(config_file)

          config = described_class.load(config_file)
          expect(config.config_source).to be_nil
        end
      end
    end
  end

  describe Clacky::ClaudeCodeEnv do
    describe ".configured?" do
      it "returns true when ANTHROPIC_API_KEY is set" do
        ClimateControl.modify(ANTHROPIC_API_KEY: "test-key") do
          expect(described_class.configured?).to be true
        end
      end

      it "returns true when ANTHROPIC_AUTH_TOKEN is set" do
        ClimateControl.modify(ANTHROPIC_AUTH_TOKEN: "test-token") do
          expect(described_class.configured?).to be true
        end
      end

      it "returns false when no auth env vars are set" do
        ClimateControl.modify(ANTHROPIC_API_KEY: nil, ANTHROPIC_AUTH_TOKEN: nil) do
          expect(described_class.configured?).to be false
        end
      end

      it "returns false when env vars are empty strings" do
        ClimateControl.modify(ANTHROPIC_API_KEY: "", ANTHROPIC_AUTH_TOKEN: "") do
          expect(described_class.configured?).to be false
        end
      end
    end

    describe ".api_key" do
      it "prefers ANTHROPIC_API_KEY over ANTHROPIC_AUTH_TOKEN" do
        ClimateControl.modify(
          ANTHROPIC_API_KEY: "api-key-value",
          ANTHROPIC_AUTH_TOKEN: "auth-token-value"
        ) do
          expect(described_class.api_key).to eq("api-key-value")
        end
      end

      it "falls back to ANTHROPIC_AUTH_TOKEN when ANTHROPIC_API_KEY is not set" do
        ClimateControl.modify(
          ANTHROPIC_API_KEY: nil,
          ANTHROPIC_AUTH_TOKEN: "fallback-token"
        ) do
          expect(described_class.api_key).to eq("fallback-token")
        end
      end
    end

    describe ".base_url" do
      it "returns custom ANTHROPIC_BASE_URL when set" do
        ClimateControl.modify(ANTHROPIC_BASE_URL: "https://custom.api.com") do
          expect(described_class.base_url).to eq("https://custom.api.com")
        end
      end

      it "returns default Anthropic API URL when not set" do
        ClimateControl.modify(ANTHROPIC_BASE_URL: nil) do
          expect(described_class.base_url).to eq("https://api.anthropic.com")
        end
      end
    end
  end
end
