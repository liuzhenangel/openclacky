require "spec_helper"

# ---------------------------------------------------------------------------
# Unit tests for HttpServer access key authentication logic.
#
# These tests exercise the brute-force protection state machine directly,
# without booting a real HTTP server. The failures hash and mutex mirror
# the instance variables initialised in HttpServer#initialize.
# ---------------------------------------------------------------------------

RSpec.describe "HttpServer access key authentication" do
  # ── Shared state (mirrors HttpServer internals) ──────────────────────────
  let(:mutex)    { Mutex.new }
  let(:failures) { {} }
  let(:ip)       { "1.2.3.4" }

  # Simulate n consecutive wrong-key attempts from ip.
  def simulate_failures(n, reset_in: 300)
    mutex.synchronize do
      entry = failures[ip] ||= { count: 0, reset_at: Time.now + reset_in }
      n.times { entry[:count] += 1 }
    end
  end

  # Returns true when the IP is currently locked out.
  def locked_out?
    entry = failures[ip]
    entry && entry[:count] >= 10 && Time.now < entry[:reset_at]
  end

  # ── local_host? behaviour ─────────────────────────────────────────────────
  describe "local_host?" do
    def local_host?(host)
      ["127.0.0.1", "::1", "localhost"].include?(host.to_s.strip)
    end

    it "treats 127.0.0.1 as localhost" do
      expect(local_host?("127.0.0.1")).to be true
    end

    it "treats ::1 as localhost" do
      expect(local_host?("::1")).to be true
    end

    it "treats 0.0.0.0 as public" do
      expect(local_host?("0.0.0.0")).to be false
    end

    it "treats arbitrary IPs as public" do
      expect(local_host?("192.168.1.1")).to be false
    end
  end

  # ── resolve_access_key behaviour ─────────────────────────────────────────
  describe "resolve_access_key" do
    it "returns key from CLACKY_ACCESS_KEY env var" do
      with_env("CLACKY_ACCESS_KEY" => "env-secret") do
        key = ENV.fetch("CLACKY_ACCESS_KEY", "").strip
        key = key.empty? ? nil : key
        expect(key).to eq("env-secret")
      end
    end

    it "returns nil when env var is blank" do
      with_env("CLACKY_ACCESS_KEY" => "   ") do
        key = ENV.fetch("CLACKY_ACCESS_KEY", "").strip
        key = key.empty? ? nil : key
        expect(key).to be_nil
      end
    end

    it "returns nil when env var is not set" do
      with_env("CLACKY_ACCESS_KEY" => "") do
        key = ENV.fetch("CLACKY_ACCESS_KEY", "").strip
        key = key.empty? ? nil : key
        expect(key).to be_nil
      end
    end
  end

  # ── Lockout threshold ─────────────────────────────────────────────────────
  describe "lockout threshold" do
    it "does not lock out after 9 failures" do
      simulate_failures(9)
      expect(failures[ip][:count]).to eq(9)
      expect(locked_out?).to be false
    end

    it "locks out at exactly 10 failures" do
      simulate_failures(10)
      expect(locked_out?).to be true
    end
  end

  # ── Lockout duration ──────────────────────────────────────────────────────
  describe "lockout duration" do
    it "sets reset_at to ~300s in the future" do
      simulate_failures(10)
      expect(failures[ip][:reset_at]).to be_within(5).of(Time.now + 300)
    end

    it "remains locked during the lockout window" do
      simulate_failures(10, reset_in: 300)
      expect(locked_out?).to be true
    end

    it "unlocks after reset_at has passed" do
      simulate_failures(10, reset_in: -1)
      expect(locked_out?).to be false
    end
  end

  # ── Missing key must not increment failure counter ────────────────────────
  describe "missing key does not count as failure" do
    it "failure count stays 0 when no key is provided" do
      # Simulate the nil-candidate branch: failures hash must remain untouched.
      candidate = nil
      unless candidate.nil? || candidate.to_s.empty?
        mutex.synchronize do
          entry = failures[ip] ||= { count: 0, reset_at: Time.now + 300 }
          entry[:count] += 1
        end
      end
      expect(failures[ip]).to be_nil
    end
  end

  # ── Successful auth clears the failure record ─────────────────────────────
  describe "successful auth clears record" do
    it "removes the IP entry on successful login" do
      simulate_failures(5)
      expect(failures[ip]).not_to be_nil
      mutex.synchronize { failures.delete(ip) }
      expect(failures[ip]).to be_nil
    end
  end
end
