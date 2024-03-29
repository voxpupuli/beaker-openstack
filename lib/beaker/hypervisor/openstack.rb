module Beaker
  #Beaker support for OpenStack
  #This code is EXPERIMENTAL!
  #Please file any issues/concerns at https://github.com/puppetlabs/beaker/issues
  class Openstack < Beaker::Hypervisor

    SLEEPWAIT = 5

    #Create a new instance of the OpenStack hypervisor object
    #@param [<Host>] openstack_hosts The array of OpenStack hosts to provision
    #@param [Hash{Symbol=>String}] options The options hash containing configuration values
    #@option options [String] :openstack_api_key The key to access the OpenStack instance with (required)
    #@option options [String] :openstack_username The username to access the OpenStack instance with (required)
    #@option options [String] :openstack_auth_url The URL to access the OpenStack instance with (required)
    #@option options [String] :openstack_tenant The tenant to access the OpenStack instance with (either this or openstack_project_name is required)
    #@option options [String] :openstack_project_name The project name to access the OpenStack instance with (either this or openstack_tenant is required)
    #@option options [String] :openstack_project_id The project id to access the OpenStack instance with (alternative to openstack_project_name)
    #@option options [String] :openstack_user_domain The user domain name to access the OpenStack instance with
    #@option options [String] :openstack_user_domain_id The user domain id to access the OpenStack instance with (alternative to openstack_user_domain)
    #@option options [String] :openstack_project_domain The project domain to access the OpenStack instance with
    #@option options [String] :openstack_project_domain_id The project domain id to access the OpenStack instance with (alternative to openstack_project_domain)
    #@option options [String] :openstack_region The region that each OpenStack instance should be provisioned on (optional)
    #@option options [String] :openstack_network The network that each OpenStack instance should be contacted through (required)
    #@option options [Bool] :openstack_floating_ip Whether a floating IP should be allocated (required)
    #@option options [String] :openstack_keyname The name of an existing key pair that should be auto-loaded onto each
    #@option options [Hash] :security_group An array of security groups to associate with the instance
    #                                            OpenStack instance (optional)
    #@option options [String] :jenkins_build_url Added as metadata to each OpenStack instance
    #@option options [String] :department Added as metadata to each OpenStack instance
    #@option options [String] :project Added as metadata to each OpenStack instance
    #@option options [Integer] :timeout The amount of time to attempt execution before quiting and exiting with failure
    def initialize(openstack_hosts, options)
      require 'fog/openstack'
      @options = options
      @logger = options[:logger]
      @hosts = openstack_hosts
      @vms = []

      raise 'You must specify an Openstack API key (:openstack_api_key) for OpenStack instances!' unless @options[:openstack_api_key]
      raise 'You must specify an Openstack username (:openstack_username) for OpenStack instances!' unless @options[:openstack_username]
      raise 'You must specify an Openstack auth URL (:openstack_auth_url) for OpenStack instances!' unless @options[:openstack_auth_url]
      raise 'You must specify an Openstack network (:openstack_network) for OpenStack instances!' unless @options[:openstack_network]
      raise 'You must specify whether a floating IP (:openstack_floating_ip) should be used for OpenStack instances!' unless !@options[:openstack_floating_ip].nil?

      is_v3 = @options[:openstack_auth_url].include?('/v3/')
      raise 'You must specify an Openstack tenant (:openstack_tenant) for OpenStack instances!' if !is_v3 and !@options[:openstack_tenant]
      raise 'You must specify an Openstack project name (:openstack_project_name) or Openstack project id (:openstack_project_id) for OpenStack instances!' if is_v3 and (!@options[:openstack_project_name] and !@options[:openstack_project_id])
      raise 'You must specify either Openstack project name (:openstack_project_name) or Openstack project id (:openstack_project_id) not both!' if is_v3 and (@options[:openstack_project_name] and @options[:openstack_project_id])
      raise 'You may specify either Openstack user domain (:openstack_user_domain) or Openstack user domain id (:openstack_user_domain_id) not both!' if is_v3 and (@options[:openstack_user_domain] and @options[:openstack_user_domain_id])
      raise 'You may specify either Openstack project domain (:openstack_project_domain) or Openstack project domain id (:openstack_project_domain_id) not both!' if is_v3 and (@options[:openstack_project_domain] and @options[:openstack_project_domain_id])
      raise 'Invalid option specified: v3 API expects :openstack_project_name or :openstack_project_id, not :openstack_tenant for OpenStack instances!' if is_v3 and @options[:openstack_tenant]
      raise 'Invalid option specified: v2 API expects :openstack_tenant, not :openstack_project_name or :openstack_project_id for OpenStack instances!' if !is_v3 and (@options[:openstack_project_name] or @options[:openstack_project_id])
      # Ensure that _id and non _id params are not mixed (due to bug in fog-openstack)
      raise 'You must not mix _id values non _id (name) values. Please use the same type for (:openstack_project_), (:openstack_user_domain) and (:openstack_project_domain)!' if is_v3 and (@options[:openstack_project_name] or @options[:openstack_user_domain] or @options[:openstack_project_domain]) and (@options[:openstack_project_id] or @options[:openstack_user_domain_id] or @options[:openstack_project_domain_id])

      # Keystone version 3 changed the parameter names
      if !is_v3
        extra_credentials = {:openstack_tenant => @options[:openstack_tenant]}
      else
        if @options[:openstack_project_id]
          extra_credentials = {:openstack_project_id => @options[:openstack_project_id]}
        else
          extra_credentials = {:openstack_project_name => @options[:openstack_project_name]}
        end
      end

      # Common keystone authentication credentials
      @credentials = {
        :provider           => :openstack,
        :openstack_auth_url => @options[:openstack_auth_url],
        :openstack_api_key  => @options[:openstack_api_key],
        :openstack_username => @options[:openstack_username],
        :openstack_tenant   => @options[:openstack_tenant],
        :openstack_region   => @options[:openstack_region],
      }.merge(extra_credentials)

      # Keystone version 3 requires users and projects to be scoped
      if is_v3
        if @options[:openstack_user_domain_id]
          @credentials[:openstack_user_domain_id] = @options[:openstack_user_domain_id]
        else
          @credentials[:openstack_user_domain]    = @options[:openstack_user_domain] || 'Default'
        end
        if @options[:openstack_project_domain_id]
          @credentials[:openstack_project_domain_id] = @options[:openstack_project_domain_id]
        else
          @credentials[:openstack_project_domain]    = @options[:openstack_project_domain] || 'Default'
        end        
      end

      @compute_client ||= Fog::Compute.new(@credentials)

      if not @compute_client
        raise "Unable to create OpenStack Compute instance (api key: #{@options[:openstack_api_key]}, username: #{@options[:openstack_username]}, auth_url: #{@options[:openstack_auth_url]}, tenant: #{@options[:openstack_tenant]}, project_name: #{@options[:openstack_project_name]})"
      end

      @network_client ||= Fog::Network.new(@credentials)

      if not @network_client
        raise "Unable to create OpenStack Network instance (api key: #{@options[:openstack_api_key]}, username: #{@options[:openstack_username]}, auth_url: #{@options[:openstack_auth_url]}, tenant: #{@options[:openstack_tenant]}, project_name: #{@options[:openstack_project_name]})"
      end

      # Validate openstack_volume_support setting value, reset to boolean if passed via ENV value string
      @options[:openstack_volume_support] = true  if @options[:openstack_volume_support].to_s.match(/\btrue\b/i)
      @options[:openstack_volume_support] = false if @options[:openstack_volume_support].to_s.match(/\bfalse\b/i)
      [true,false].include? @options[:openstack_volume_support] or raise "Invalid openstack_volume_support setting, current: @options[:openstack_volume_support]"

    end

    #Provided a flavor name return the OpenStack id for that flavor
    #@param [String] f The flavor name
    #@return [String] Openstack id for provided flavor name
    def flavor f
      @logger.debug "OpenStack: Looking up flavor '#{f}'"
      @compute_client.flavors.find { |x| x.name == f } || raise("Couldn't find flavor: #{f}")
    end

    #Provided an image name return the OpenStack id for that image
    #@param [String] i The image name
    #@return [String] Openstack id for provided image name
    def image i
      @logger.debug "OpenStack: Looking up image '#{i}'"
      @compute_client.images.find { |x| x.name == i } || raise("Couldn't find image: #{i}")
    end

    #Provided a network name return the OpenStack id for that network
    #@param [String] n The network name
    #@return [String] Openstack id for provided network name
    def network n
      @logger.debug "OpenStack: Looking up network '#{n}'"
      @network_client.networks.find { |x| x.name == n } || raise("Couldn't find network: #{n}")
    end

    #Provided an array of security groups return that array if all
    #security groups are present
    #@param [Array] sgs The array of security group names
    #@return [Array] The array of security group names
    def security_groups sgs
      for sg in sgs
        @logger.debug "Openstack: Looking up security group '#{sg}'"
        @compute_client.security_groups.find { |x| x.name == sg } || raise("Couldn't find security group: #{sg}")
        sgs
      end
    end

    # Create a volume client on request
    # @return [Fog::OpenStack::Volume] OpenStack volume client
    def volume_client_create
      @volume_client ||= Fog::Volume.new(@credentials)
      unless @volume_client
        raise "Unable to create OpenStack Volume instance"\
          " (api_key: #{@options[:openstack_api_key]},"\
        " username: #{@options[:openstack_username]},"\
        " auth_url: #{@options[:openstack_auth_url]},"\
        " tenant: #{@options[:openstack_tenant]})"
      end
    end

    # Get a hash of volumes from the host
    def get_volumes host
      return host['volumes'] if host['volumes']
      {}
    end

    # Get the API version
    def get_volume_api_version
      case @volume_client
      when Fog::Volume::OpenStack::V1
        1
      else
        -1
      end
    end

    # Create and attach dynamic volumes
    #
    # Creates an array of volumes and attaches them to the current host.
    # The host bus type is determined by the image type, so by default
    # devices appear as /dev/vdb, /dev/vdc etc.  Setting the glance
    # properties hw_disk_bus=scsi, hw_scsi_model=virtio-scsi will present
    # them as /dev/sdb, /dev/sdc (or 2:0:0:1, 2:0:0:2 in SCSI addresses)
    #
    # @param host [Hash] thet current host defined in the nodeset
    # @param vm [Fog::Compute::OpenStack::Server] the server to attach to
    def provision_storage host, vm
      volumes = get_volumes(host)
      if !volumes.empty?
        # Lazily create the volume client if needed
        volume_client_create
        volumes.keys.each_with_index do |volume, index|
          @logger.debug "Creating volume #{volume} for OpenStack host #{host.name}"

          # The node defintion file defines volume sizes in MB (due to precedent
          # with the vagrant virtualbox implementation) however OpenStack requires
          # this translating into GB
          openstack_size = volumes[volume]['size'].to_i / 1000

          # Set up the volume creation arguments
          args = {
            :size        => openstack_size,
            :description => "Beaker volume: host=#{host.name} volume=#{volume}",
          }

          # Between version 1 and subsequent versions the API was updated to
          # rename 'display_name' to just 'name' for better consistency
          if get_volume_api_version == 1
            args[:display_name] = volume
          else
            args[:name] = volume
          end

          # Create the volume and wait for it to become available
          vol = @volume_client.volumes.create(**args)
          vol.wait_for { ready? }

          # Fog needs a device name to attach as, so invent one.  The guest
          # doesn't pay any attention to this
          device = "/dev/vd#{('b'.ord + index).chr}"
          vm.attach_volume(vol.id, device)
        end
      end
    end

    # Detach and delete guest volumes
    # @param vm [Fog::Compute::OpenStack::Server] the server to detach from
    def cleanup_storage vm
      vm.volumes.each do |vol|
        @logger.debug "Deleting volume #{vol.name} for OpenStack host #{vm.name}"
        vm.detach_volume(vol.id)
        vol.wait_for { ready? }
        vol.destroy
      end
    end

    # Get a floating IP address to associate with the instance, try
    # to allocate a new one from the specified pool if none are available
    #
    # TODO(GiedriusS): convert to use @network_client. This API will be turned off
    # completely very soon.
    def get_floating_ip
      begin
        @logger.debug "Creating IP"
        ip = @compute_client.addresses.create
      rescue Fog::OpenStack::Compute::NotFound
        # If there are no more floating IP addresses, allocate a
        # new one and try again.
        @compute_client.allocate_address(@options[:floating_ip_pool])
        ip = @compute_client.addresses.find { |ip| ip.instance_id.nil? }
      end
      ip
    end

    # Create new instances in OpenStack, depending on if create_in_parallel is true or not
    def provision
      if @options[:create_in_parallel]
        # Enable abort on exception for threads
        Thread.abort_on_exception = true
        @logger.notify "Provisioning OpenStack in parallel"
        provision_parallel
      else
        @logger.notify "Provisioning OpenStack sequentially"
        provision_sequential
      end
      hack_etc_hosts @hosts, @options
    end

    # Parallel creation wrapper
    def provision_parallel
      # Array to store threads
      threads = @hosts.map do |host|
        Thread.new do
          create_instance_resources(host)
        end
      end
      # Wait for all threads to finish
      threads.each(&:join)
    end

    # Sequential creation wrapper
    def provision_sequential
      @hosts.each do |host|
        create_instance_resources(host)
      end
    end

    # Create the actual instance resources
    def create_instance_resources(host)
      @logger.notify "Provisioning OpenStack"
      if @options[:openstack_floating_ip]
        ip = get_floating_ip
        hostname = ip.ip.gsub('.', '-')
        host[:vmhostname] = hostname + '.rfc1918.puppetlabs.net'
      else
        hostname = ('a'..'z').to_a.shuffle[0, 10].join
        host[:vmhostname] = hostname
      end

      create_or_associate_keypair(host, hostname)
      @logger.debug "Provisioning #{host.name} (#{host[:vmhostname]})"
      options = {
        :flavor_ref => flavor(host[:flavor]).id,
        :image_ref  => image(host[:image]).id,
        :nics       => [{'net_id' => network(@options[:openstack_network]).id}],
        :name       => host[:vmhostname],
        :hostname   => host[:vmhostname],
        :user_data  => host[:user_data] || "#cloud-config\nmanage_etc_hosts: true\n",
        :key_name   => host[:keyname],
      }
      options[:security_groups] = security_groups(@options[:security_group]) unless @options[:security_group].nil?
      vm = @compute_client.servers.create(options)

      # Wait for the new instance to start up
      try = 1
      attempts = @options[:timeout].to_i / SLEEPWAIT

      while try <= attempts
        begin
          vm.wait_for(5) { ready? }
          break
        rescue Fog::Errors::TimeoutError => e
          if try >= attempts
            @logger.debug "Failed to connect to new OpenStack instance #{host.name} (#{host[:vmhostname]})"
            raise e
          end
          @logger.debug "Timeout connecting to instance #{host.name} (#{host[:vmhostname]}), trying again..."
        end
        sleep SLEEPWAIT
        try += 1
      end

      if @options[:openstack_floating_ip]
        # Associate a public IP to the VM
        ip.server = vm
        host[:ip] = ip.ip
      else
        # Get the first address of the VM that was just created just like in the
        # OpenStack UI
        host[:ip] = vm.addresses.first[1][0]["addr"]
      end

      @logger.debug "OpenStack host #{host.name} (#{host[:vmhostname]}) assigned ip: #{host[:ip]}"
    
      # Set metadata
      vm.metadata.update({:jenkins_build_url => @options[:jenkins_build_url].to_s,
                          :department        => @options[:department].to_s,
                          :project           => @options[:project].to_s })
      @vms << vm

      # Wait for the host to accept SSH logins
      host.wait_for_port(22)

      # Enable root if the user is not root
      enable_root(host)

      provision_storage(host, vm) if @options[:openstack_volume_support]
      @logger.notify "OpenStack Volume Support Disabled, can't provision volumes" if not @options[:openstack_volume_support]

    # Handle exceptions in the thread
    rescue => e
      @logger.error "Thread #{host} failed with error: #{e.message}"
      # Call cleanup function to delete orphaned hosts
      cleanup
      # Pass the error to the main thread to terminate all threads
      Thread.main.raise(e)
      # Terminate the current thread (to prevent hack_etc_hosts trying to run after error raised)
      Thread.kill(Thread.current)
    end

    # Destroy any OpenStack instances
    def cleanup
      @logger.notify "Cleaning up OpenStack"
      @vms.each do |vm|
        cleanup_storage(vm) if @options[:openstack_volume_support]
        @logger.debug "Release floating IPs for OpenStack host #{vm.name}"
        floating_ips = vm.all_addresses # fetch and release its floating IPs
        floating_ips.each do |address|
          @compute_client.disassociate_address(vm.id, address['ip'])
          @compute_client.release_address(address['id'])
        end
        @logger.debug "Destroying OpenStack host #{vm.name}"
        vm.destroy
        if @options[:openstack_keyname].nil?
          @logger.debug "Deleting random keypair"
          @compute_client.delete_key_pair vm.key_name
        end
      end
    end

    # Enables root access for a host when username is not root
    # This method ripped from the aws_sdk implementation and is probably wrong
    # because it iterates on a collection when there's no guarantee the collection
    # has all been brought up in openstack yet and will thus explode
    # @return [void]
    # @api private
    def enable_root_on_hosts
      @hosts.each do |host|
        enable_root(host)
      end
    end

    # Enable root on a single host (the current one presumably) but only
    # if the username isn't 'root'
    def enable_root(host)
      if host['user'] != 'root'
        copy_ssh_to_root(host, @options)
        enable_root_login(host, @options)
        host['user'] = 'root'
        host.close
      end
    end

    #Get key_name from options or generate a new rsa key and add it to
    #OpenStack keypairs
    #
    #@param [Host] host The OpenStack host to provision
    #@api private
    def create_or_associate_keypair(host, keyname)
      if @options[:openstack_keyname]
        @logger.debug "Adding optional key_name #{@options[:openstack_keyname]} to #{host.name} (#{host[:vmhostname]})"
        keyname = @options[:openstack_keyname]
      else
        @logger.debug "Generate a new rsa key"

        # There is apparently an error that can occur when generating RSA keys, probably
        # due to some timing issue, probably similar to the issue described here:
        # https://github.com/negativecode/vines/issues/34
        # In order to mitigate this error, we will simply try again up to three times, and
        # then fail if we continue to error out.
        begin
          retries ||= 0
          key = OpenSSL::PKey::RSA.new 2048
        rescue OpenSSL::PKey::RSAError => e
          retries += 1
          if retries > 2
            @logger.notify "error generating RSA key #{retries} times, exiting"
            raise e
          end
          retry
        end

        type = key.ssh_type
        data = [ key.to_blob ].pack('m0')
        @logger.debug "Creating Openstack keypair '#{keyname}' for public key '#{type} #{data}'"
        @compute_client.create_key_pair keyname, "#{type} #{data}"
        host['ssh'][:key_data] = [ key.to_pem ]
      end

      host[:keyname] = keyname
    end
  end
end
