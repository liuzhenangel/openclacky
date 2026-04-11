# frozen_string_literal: true

module Clacky
  module DeployTools
    # Trigger a Railway deployment via `railway up` (blocking, with live logs).
    # Uses RAILWAY_TOKEN passed through environment — no clackycli wrapper needed.
    class ExecuteDeployment

      # Trigger deployment for a service (blocking - waits for completion).
      #
      # @param service_name   [String] Railway service name (from railway.toml or service list)
      # @param platform_token [String] RAILWAY_TOKEN for this deploy task
      # @return [Hash] { success: true, url: String } or { success: false, error: String }
      def self.execute(service_name:, platform_token:)
        if service_name.nil? || service_name.strip.empty?
          return { success: false, error: "service_name is required" }
        end

        if platform_token.nil? || platform_token.strip.empty?
          return { success: false, error: "platform_token is required" }
        end

        puts "🚀 Deploying service: #{service_name}"
        puts "    (This may take several minutes - you'll see live build logs below)"
        puts ""

        env = { "RAILWAY_TOKEN" => platform_token }
        
        # Use railway up without --detach to block and show live logs
        success = system(
          env,
          "railway", "up", "--service", service_name,
          in: :close  # Don't redirect stdout/stderr - let user see live logs
        )

        if success
          puts ""
          puts "✅ Deployment completed successfully"
          
          # Extract URL from railway status after successful deployment
          url = extract_url(env, service_name)
          
          return { success: true, url: url }
        else
          puts ""
          puts "❌ Deployment failed"
          return { success: false, error: "railway up exited with error code" }
        end

      rescue => e
        { success: false, error: "Unexpected error: #{e.message}" }
      end

      private_class_method def self.extract_url(env, service_name)
        require "json"
        require "tempfile"
        
        Tempfile.create("railway_status") do |tmpfile|
          system(
            env,
            "railway", "status", "--json",
            in: :close,
            out: tmpfile,
            err: File::NULL
          )
          
          tmpfile.rewind
          output = tmpfile.read.strip
          return nil if output.empty?
          
          status_data = JSON.parse(output)
          
          # Navigate: environments.edges[].node (name="production").serviceInstances.edges[].node
          env_edges = status_data.dig("environments", "edges")
          return nil unless env_edges.is_a?(Array)
          
          prod_env = env_edges.find { |e| e.dig("node", "name") == "production" }
          return nil unless prod_env
          
          service_edges = prod_env.dig("node", "serviceInstances", "edges")
          return nil unless service_edges.is_a?(Array)
          
          service_edge = service_edges.find do |edge|
            edge.dig("node", "serviceName") == service_name
          end
          return nil unless service_edge
          
          domains = service_edge.dig("node", "domains", "customDomains")
          return nil unless domains.is_a?(Array) && !domains.empty?
          
          domain = domains.first["domain"]
          domain ? "https://#{domain}" : nil
        end
      rescue
        nil
      end
    end
  end
end
