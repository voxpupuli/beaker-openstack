module Beaker
  # Beaker support for OpenStack
  # Please file any issues/concerns at https://github.com/voxpupuli/beaker-openstack/issues

  # Additional volumes created via openstack_volume_support are preserved and not deleted by cleanup
  class Openstack < Beaker::Hypervisor

    SLEEPWAIT = 5  # Seconds to wait between retry attempts for VM boot

    # Create a new OpenStack hypervisor object
    #
    # @param [Array<Host>] openstack_hosts Array of hosts to provision
    # @param [Hash{Symbol=>Object}] options Configuration options:
    # @option options [String] :openstack_api_key Required API key
    # @option options [String] :openstack_username Required username
    # @option options [String] :openstack_auth_url Required auth URL
    # @option options [String] :openstack_project_name Project name (v3) or nil
    # @option options [String] :openstack_project_id Project ID (v3) or nil
    # @option options [String] :openstack_user_domain Optional user domain for v3
    # @option options [String] :openstack_user_domain_id Optional user domain ID for v3
    # @option options [String] :openstack_project_domain Optional project domain for v3
    # @option options [String] :openstack_project_domain_id Optional project domain ID for v3
    # @option options [String] :openstack_region The region that each OpenStack instance should be provisioned on (optional)
    # @option options [String] :openstack_network Required network for VM
    # @option options [Bool] :openstack_floating_ip Whether to assign a floating IP
    # @option options [String] :floating_ip_pool Required floating network ID when floating IPs are enabled
    # @option options [Bool] :openstack_volume_support Whether to provision additional volumes
    # @option options [String] :openstack_keyname Optional pre-existing keypair name
    # @option options [Array<String>] :security_group Optional security groups
    # @option options [Integer] :timeout Timeout in seconds for VM boot
    # @option options [String] :jenkins_build_url Optional metadata
    # @option options [String] :department Optional metadata
    # @option options [String] :project Optional metadata
    def initialize(openstack_hosts, options)
      require 'fog/openstack'

      @options = options
      @logger  = options[:logger]
      @hosts   = openstack_hosts

      # Initialize shared resources and mutexes for thread safety
      @vms = []
      @vms_mutex = Mutex.new
      @keypairs_mutex = Mutex.new
      @cleanup_mutex = Mutex.new
      @cleanup_ran = false

      # Track keys we create so we only delete what we own
      @ephemeral_keypairs = []

      # Required options
      raise 'You must specify :openstack_api_key'      unless @options[:openstack_api_key]
      raise 'You must specify :openstack_username'     unless @options[:openstack_username]
      raise 'You must specify :openstack_auth_url'     unless @options[:openstack_auth_url]
      raise 'You must specify :openstack_network'      unless @options[:openstack_network]
      raise 'You must specify :openstack_floating_ip (true/false)' if @options[:openstack_floating_ip].nil?

      # Floating IP pool is required only if floating IPs are enabled
      raise 'You must specify :floating_ip_pool when using floating IPs' if @options[:openstack_floating_ip] && !@options[:floating_ip_pool]

      # Keystone version detection
      # Matches both /v3 and /v3/ endings to avoid false negatives
      is_v3 = @options[:openstack_auth_url].match?(%r{/v3/?$})

      # Enforce Keystone v3 only (v2 is no longer supported)
      raise 'Keystone v2 is no longer supported. Please use a /v3 auth URL.' unless is_v3

      # project_name or project_id required
      raise 'Specify project_name or project_id' unless @options[:openstack_project_name] || @options[:openstack_project_id]

      # cannot specify both
      raise 'Do not mix project_name and project_id' if @options[:openstack_project_name] && @options[:openstack_project_id]

      # user_domain XOR user_domain_id
      raise 'Specify either :openstack_user_domain or :openstack_user_domain_id, not both' if @options[:openstack_user_domain] && @options[:openstack_user_domain_id]

      # project_domain XOR project_domain_id
      raise 'Specify either :openstack_project_domain or :openstack_project_domain_id, not both' if @options[:openstack_project_domain] && @options[:openstack_project_domain_id]

      # fog-openstack limitation: do not mix _id and non-_id fields
      if (@options[:openstack_project_name] ||
          @options[:openstack_user_domain] ||
          @options[:openstack_project_domain]) &&
         (@options[:openstack_project_id] ||
          @options[:openstack_user_domain_id] ||
          @options[:openstack_project_domain_id])
        raise 'Do not mix _id and non-_id values for project/user domains due to fog-openstack limitations'
      end

      # Build credential scope depending on Keystone version
      extra_credentials =
        if @options[:openstack_project_id]
          { openstack_project_id: @options[:openstack_project_id] }
        else
          { openstack_project_name: @options[:openstack_project_name] }
        end

      # Base credentials (no duplicate tenant/project fields)
      @credentials = {
        provider: :openstack,
        openstack_auth_url: @options[:openstack_auth_url],
        openstack_api_key: @options[:openstack_api_key],
        openstack_username: @options[:openstack_username],
        openstack_region: @options[:openstack_region]
      }.merge(extra_credentials)

      # Keystone v3 domain scoping
      @credentials[:openstack_user_domain_id] = @options[:openstack_user_domain_id] if @options[:openstack_user_domain_id]
      @credentials[:openstack_user_domain] ||= @options[:openstack_user_domain] || 'Default'

      @credentials[:openstack_project_domain_id] = @options[:openstack_project_domain_id] if @options[:openstack_project_domain_id]
      @credentials[:openstack_project_domain] ||= @options[:openstack_project_domain] || 'Default'

      # Create clients
      # These are created once during initialization (no memoization needed)
      @compute_client = Fog::Compute.new(@credentials)
      raise "Unable to create OpenStack Compute instance" unless @compute_client

      @network_client = Fog::Network.new(@credentials)
      raise "Unable to create OpenStack Network instance" unless @network_client

      # --- openstack_volume_support normalization ---
      # Accepts string or boolean input, but only true/false are valid outcomes
      val = @options[:openstack_volume_support].to_s.downcase
      @options[:openstack_volume_support] = true  if val == "true"
      @options[:openstack_volume_support] = false if val == "false"

      raise "Invalid openstack_volume_support setting" unless [true, false].include?(@options[:openstack_volume_support])
    end

    # @!group Provision Methods
    # Main provisioning entrypoint
    def provision
      if @options[:create_in_parallel]
        Thread.abort_on_exception = true
        @logger.notify "Provisioning OpenStack in parallel"
        provision_parallel
      else
        @logger.notify "Provisioning OpenStack sequentially"
        provision_sequential
      end

      hack_etc_hosts @hosts, @options
    end

    def provision_parallel
      threads = @hosts.map { |host| Thread.new { create_instance_resources(host) } }
      threads.each(&:join)
    end

    def provision_sequential
      @hosts.each { |host| create_instance_resources(host) }
    end

    # Create all resources required for a single VM
    def create_instance_resources(host)
      @logger.notify "Provisioning #{host.name}"

      if @options[:openstack_floating_ip]
        ip = get_floating_ip
        host[:vmhostname] = "#{ip.ip.tr('.', '-')}.rfc1918.puppetlabs.net"
      else
        host[:vmhostname] = ('a'..'z').to_a.sample(10).join
      end

      create_or_associate_keypair(host, host[:vmhostname])

      server_opts = {
        name: host[:vmhostname],
        flavor_ref: flavor(host[:flavor]).id,
        nics: [{ 'net_id' => network(@options[:openstack_network]).id }],
        key_name: host[:keyname],
        security_groups: @options[:security_group] ? security_groups(@options[:security_group]) : nil,
        user_data: host[:user_data] || "#cloud-config\nmanage_etc_hosts: true\n"
      }

      if boot_from_volume?(host)
        server_opts[:block_device_mapping_v2] = [{
          uuid: image(host[:image]).id,
          source_type: "image",
          destination_type: "volume",
          volume_size: host['root_volume']['size'].to_i,
          delete_on_termination: host['root_volume'].key?('delete_on_termination') ? !!host['root_volume']['delete_on_termination'] : true,
          boot_index: 0
        }]
      else
        server_opts[:image_ref] = image(host[:image]).id
      end

      vm = @compute_client.servers.create(server_opts)
      vm.wait_for(@options[:timeout] || 600) { respond_to?(:ready?) ? ready? : state == 'ACTIVE' }

      if @options[:openstack_floating_ip]
        ip.server = vm
        host[:ip] = ip.ip
      else
        # Prefer IPv4 address if multiple networks exist
        addr = vm.addresses.values.flatten.find { |a| a['version'] == 4 }
        host[:ip] = addr && addr['addr']

        if host[:ip].nil?
          @logger.warn "No IPv4 address found for #{host.name}; VM may be IPv6-only"
        end
      end

      @logger.debug "Assigned IP #{host[:ip]}"

      # Metadata is best-effort (some clouds disable it)
      vm.metadata.update(
        jenkins_build_url: @options[:jenkins_build_url].to_s,
        department: @options[:department].to_s,
        project: @options[:project].to_s
      ) rescue @logger.debug("Metadata update failed")

      @vms_mutex.synchronize { @vms << vm }

      host.wait_for_port(22)
      enable_root(host)

      provision_storage(host, vm) if @options[:openstack_volume_support]

    rescue => e
      @logger.error "Provision failed: #{e.message}"

      @cleanup_mutex.synchronize do
        unless @cleanup_ran
          @cleanup_ran = true
          cleanup
        end
      end

      raise e
    end

    # Get key_name from options or generate a new RSA key and add it to OpenStack keypairs
    def create_or_associate_keypair(host, keyname)
      if @options[:openstack_keyname]
        host[:keyname] = @options[:openstack_keyname]
        @logger.debug "Using existing keypair #{@options[:openstack_keyname]}"
      else
        # Remove any existing ephemeral key with this name to avoid collisions
        @compute_client.key_pairs.get(keyname)&.destroy

        # Generate new RSA keypair
        key = OpenSSL::PKey::RSA.new(2048)
        type = key.ssh_type
        data = [key.to_blob].pack('m0')
        @compute_client.create_key_pair keyname, "#{type} #{data}"

        # Track ephemeral keypairs for cleanup
        @keypairs_mutex.synchronize { @ephemeral_keypairs << keyname }

        # Inject private key into Beaker host
        host['ssh'][:key_data] = [key.to_pem]
        host[:keyname] = keyname
      end
    end

    # Get a floating IP address from the configured pool
    # Always allocates a new floating IP (no reuse logic)
    def get_floating_ip
      @network_client.floating_ips.create(
        floating_network_id: @options[:floating_ip_pool]
      )
    end

    # Provision additional volumes (always preserved, never deleted automatically)
    def provision_storage(host, vm)
      return unless @options[:openstack_volume_support]

      volumes = get_volumes(host)
      return if volumes.empty?

      volume_client_create
      device_index = 0

      volumes.each do |vol_name, vol_def|
        # Skip root volume if already handled via boot_from_volume
        next if vol_name == 'root' && boot_from_volume?(host)

        @logger.debug "Creating volume #{vol_name} for #{host.name}"

        vol = @volume_client.volumes.create(
          name: vol_name,
          size: vol_def['size'].to_i,
          description: vol_def['description'] || "Beaker volume: #{host.name}:#{vol_name}"
        )

        # Wait for Cinder to fully provision the volume
        vol.wait_for(300) do
          vol.reload
          raise "Volume #{vol.name} entered error state: #{vol.status}" if vol.status =~ /error/i
          vol.status == 'available'
        end

        # Device naming starts at /dev/vdc to avoid conflicts with root/ephemeral disks
        device_letter = ('c'.ord + device_index)
        raise "Too many volumes, cannot allocate device name" if device_letter > 'z'.ord
        device = "/dev/vd#{device_letter.chr}"
        device_index += 1

        # Attach with retry (Nova attach sometimes races)
        attempts = 0
        begin
          vm.attach_volume(vol.id, device)
        rescue => e
          attempts += 1
          retry if attempts < 3 && sleep(2).nil?
          raise "Failed to attach volume #{vol_name}: #{e}"
        end

        # Wait for Nova to complete attachment
        vol.wait_for(120) do
          vol.reload
          vol.status == 'in-use'
        end
      end
    end

    # Enables root access for a single host when its current user is not 'root'
    def enable_root(host)
      return if host['user'] == 'root'
      copy_ssh_to_root(host, @options)
      enable_root_login(host, @options)
      host['user'] = 'root'
      host.close
    end

    # Cleanup all resources
    # Only ephemeral keypairs are deleted; VMs are destroyed; additional volumes are preserved
    def cleanup
      @logger.notify "Cleaning up OpenStack"

      @vms_mutex.synchronize do
        @vms.each do |vm|
          begin
            @logger.debug "Destroying #{vm.name}"
            vm.destroy rescue nil
          rescue => e
            @logger.error "Cleanup error: #{e.message}"
          end
        end
        @vms.clear
      end

      @keypairs_mutex.synchronize do
        @ephemeral_keypairs.each do |keyname|
          begin
            @compute_client.key_pairs.get(keyname)&.destroy
          rescue => e
            @logger.error "Failed to delete ephemeral keypair #{keyname}: #{e.message}"
          end
        end
        @ephemeral_keypairs.clear
      end
    end

    # @!group Lookup Methods
    # Lookup flavor by name
    def flavor(f)
      @logger.debug "Looking up flavor '#{f}'"
      @compute_client.flavors.find { |x| x.name == f } || raise("Couldn't find flavor: #{f}")
    end

    # Lookup image by name
    def image(i)
      @logger.debug "Looking up image '#{i}'"
      @compute_client.images.find { |x| x.name == i } || raise("Couldn't find image: #{i}")
    end

    # Lookup network by name
    def network(n)
      @logger.debug "Looking up network '#{n}'"
      @network_client.networks.find { |x| x.name == n } || raise("Couldn't find network: #{n}")
    end

    # Validate security groups exist and return them in Fog-compatible format
    def security_groups(sgs)
      sgs.each do |sg|
        @logger.debug "Openstack: Looking up security group '#{sg}'"
        @compute_client.security_groups.find { |x| x.name == sg } || raise("Couldn't find security group: #{sg}")
      end

      # Return an array of strings, not hashes
      sgs
    end

    # Determine if host should boot from volume
    def boot_from_volume?(host)
      host['root_volume'] && host['root_volume']['size']
    end

    # Lazy-init volume client
    def volume_client_create
      @volume_client ||= Fog::Volume.new(@credentials)
    end

    # Retrieve additional volumes definition from host
    def get_volumes(host)
      host['volumes'] || {}
    end
  end
end
