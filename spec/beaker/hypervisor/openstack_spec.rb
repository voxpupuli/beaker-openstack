require 'spec_helper'
require 'fog/openstack'

module Beaker
  describe Openstack do

    let(:options) do
      make_opts.merge(
        'logger' => double.as_null_object,
        'openstack_floating_ip' => true,
        'floating_ip_pool' => 'my_pool'
      )
    end

    let(:openstack) { Openstack.new(@hosts, options) }

    before :each do
      @hosts = make_hosts()

      @compute_client = double.as_null_object
      @network_client = double.as_null_object

      allow(Fog::Compute).to receive(:new).and_return(@compute_client)
      allow(Fog::Network).to receive(:new).and_return(@network_client)
    end

    # -------------------------------------------------------------------------
    # Keystone version tests
    # -------------------------------------------------------------------------
    context 'keystone version support' do
      it 'supports keystone v2' do
        credentials = openstack.instance_eval('@credentials')
        expect(credentials[:openstack_tenant]).to eq('testing')
        expect(credentials[:openstack_user_domain]).to be_nil
        expect(credentials[:openstack_project_domain]).to be_nil
      end

      it 'supports keystone v3 with implicit defaults' do
        v3 = options.dup
        v3[:openstack_auth_url] = 'https://example.com/identity/v3'
        v3[:openstack_project_name] = 'TeamTest'
        v3[:openstack_tenant] = nil

        creds = Openstack.new(@hosts, v3).instance_eval('@credentials')
        expect(creds[:openstack_project_name]).to eq('TeamTest')
        expect(creds[:openstack_user_domain]).to eq('Default')
        expect(creds[:openstack_project_domain]).to eq('Default')
      end

      it 'supports keystone v3 with explicit domains' do
        v3 = options.dup
        v3[:openstack_auth_url] = 'https://example.com/identity/v3'
        v3[:openstack_project_name] = 'TeamTest'
        v3[:openstack_user_domain] = 'acme'
        v3[:openstack_project_domain] = 'rnd'
        v3[:openstack_tenant] = nil

        creds = Openstack.new(@hosts, v3).instance_eval('@credentials')
        expect(creds[:openstack_user_domain]).to eq('acme')
        expect(creds[:openstack_project_domain]).to eq('rnd')
      end
    end

    # -------------------------------------------------------------------------
    # Provision tests
    # -------------------------------------------------------------------------
    describe '#provision' do
      it 'initializes options correctly' do
        opts = openstack.instance_eval('@options')
        expect(opts['openstack_api_key']).to eq('P1as$w0rd')
        expect(opts['openstack_username']).to eq('user')
        expect(opts['openstack_auth_url']).to eq('http://openstack_hypervisor.labs.net:5000/v2.0/tokens')
        expect(opts['openstack_network']).to eq('testing')
        expect(opts['security_group']).to eq(['my_sg', 'default'])
        expect(opts['floating_ip_pool']).to eq('my_pool')
      end

      it 'initializes host defaults' do
        @hosts.each do |host|
          expect(host['image']).to eq('default_image')
          expect(host['flavor']).to eq('m1.large')
          expect(host['user_data']).to eq('#cloud-config\nmanage_etc_hosts: true\nfinal_message: "The host is finally up!"')
        end
      end

      it 'passes correct parameters to server creation' do
        mock_flavor = double(id: 12345)
        mock_image  = double(id: 54321)

        allow(openstack).to receive(:flavor).and_return(mock_flavor)
        allow(openstack).to receive(:image).and_return(mock_image)

        mock_servers = double.as_null_object
        allow(@compute_client).to receive(:servers).and_return(mock_servers)

        expect(mock_servers).to receive(:create).with(hash_including(
          flavor_ref: 12345,
          user_data: '#cloud-config\nmanage_etc_hosts: true\nfinal_message: "The host is finally up!"'
        ))

        @hosts.each { |h| allow(h).to receive(:wait_for_port).and_return(true) }

        mock_ip = double(ip: '172.16.0.1')
        allow(mock_ip).to receive(:server=)
        allow(openstack).to receive(:get_floating_ip).and_return(mock_ip)

        openstack.provision
      end

      it 'generates valid keynames' do
        mock_ip = double(ip: '172.16.0.1')
        allow(mock_ip).to receive(:server=)
        allow(openstack).to receive(:get_floating_ip).and_return(mock_ip)
        openstack.instance_eval('@options')['openstack_keyname'] = nil

        @hosts.each { |h| allow(h).to receive(:wait_for_port).and_return(true) }

        openstack.provision

        @hosts.each do |host|
          expect(host[:keyname]).to match(/^[A-Za-z0-9.\-_]+$/)
        end
      end

      it 'allocates a new floating IP each time' do
        mock_fips = double.as_null_object
        allow(@network_client).to receive(:floating_ips).and_return(mock_fips)
        expect(mock_fips).to receive(:create).exactly(3).times

        3.times { openstack.get_floating_ip }
      end

      it 'attempts metadata update but rescues failures' do
        mock_flavor = double(id: 12345)
        mock_image  = double(id: 54321)

        allow(openstack).to receive(:flavor).and_return(mock_flavor)
        allow(openstack).to receive(:image).and_return(mock_image)

        mock_servers = double.as_null_object
        allow(@compute_client).to receive(:servers).and_return(mock_servers)

        vm = double(as_null_object: true)
        allow(vm).to receive(:wait_for)
        allow(mock_servers).to receive(:create).and_return(vm)

        mock_metadata = double()
        allow(vm).to receive(:metadata).and_return(mock_metadata)
        allow(mock_metadata).to receive(:update).and_raise("metadata disabled")

        mock_ip = double(ip: '172.16.0.1')
        allow(mock_ip).to receive(:server=)
        allow(openstack).to receive(:get_floating_ip).and_return(mock_ip)

        @hosts.each { |h| allow(h).to receive(:wait_for_port).and_return(true) }

        expect { openstack.provision }.not_to raise_error
      end

      # ---------------------------------------------------------------------
      # Boot-from-volume test
      # ---------------------------------------------------------------------
      it 'uses block_device_mapping_v2 when boot_from_volume is enabled' do
        host = @hosts.first
        host['boot_from_volume'] = true
        host['root_volume'] = { 'size' => 20 }

        mock_flavor = double(id: 12345)
        mock_image  = double(id: 'img-123')

        allow(openstack).to receive(:flavor).and_return(mock_flavor)
        allow(openstack).to receive(:image).and_return(mock_image)

        mock_servers = double.as_null_object
        allow(@compute_client).to receive(:servers).and_return(mock_servers)

        expect(mock_servers).to receive(:create).with(hash_including(
          flavor_ref: 12345,
          block_device_mapping_v2: [
            hash_including(
              boot_index: 0,
              uuid: 'img-123',
              source_type: 'image',
              destination_type: 'volume',
              volume_size: 20
            )
          ]
        ))

        @hosts.each { |h| allow(h).to receive(:wait_for_port).and_return(true) }

        mock_ip = double(ip: '172.16.0.1')
        allow(mock_ip).to receive(:server=)
        allow(openstack).to receive(:get_floating_ip).and_return(mock_ip)

        openstack.provision
      end
    end

    # -------------------------------------------------------------------------
    # Volume support tests
    # -------------------------------------------------------------------------
    context 'volume creation option' do
      it 'calls provision_storage when enabled' do
        mock_flavor = double(id: 12345)
        mock_image  = double(id: 54321)

        allow(openstack).to receive(:flavor).and_return(mock_flavor)
        allow(openstack).to receive(:image).and_return(mock_image)

        mock_servers = double.as_null_object
        allow(@compute_client).to receive(:servers).and_return(mock_servers)

        @hosts.each do |host|
          allow(host).to receive(:wait_for_port).and_return(true)
          expect(openstack).to receive(:provision_storage)
        end

        mock_ip = double(ip: '172.16.0.1')
        allow(mock_ip).to receive(:server=)
        allow(openstack).to receive(:get_floating_ip).and_return(mock_ip)

        openstack.provision
      end

      it 'skips provision_storage when disabled' do
        openstack.instance_eval('@options')[:openstack_volume_support] = false

        mock_flavor = double(id: 12345)
        mock_image  = double(id: 54321)

        allow(openstack).to receive(:flavor).and_return(mock_flavor)
        allow(openstack).to receive(:image).and_return(mock_image)

        mock_servers = double.as_null_object
        allow(@compute_client).to receive(:servers).and_return(mock_servers)

        @hosts.each do |host|
          allow(host).to receive(:wait_for_port).and_return(true)
          expect(openstack).not_to receive(:provision_storage)
        end

        mock_ip = double(ip: '172.16.0.1')
        allow(mock_ip).to receive(:server=)
        allow(openstack).to receive(:get_floating_ip).and_return(mock_ip)

        openstack.provision
      end
    end

    # -------------------------------------------------------------------------
    # provision_storage tests
    # -------------------------------------------------------------------------
    describe '#provision_storage' do
      it 'creates and attaches volumes' do
        allow(openstack).to receive(:get_volumes).and_return({
          'vol1' => { 'size' => 10 }
        })

        client = double.as_null_object
        openstack.instance_variable_set(:@volume_client, client)

        mock_volume = double(status: 'available', as_null_object: true)
        expect(client).to receive(:volumes).and_return(double(create: mock_volume))

        allow(mock_volume).to receive(:wait_for).and_return(true)
        allow(mock_volume).to receive(:id).and_return('vol-id')

        mock_vm = double.as_null_object
        expect(mock_vm).to receive(:attach_volume).with('vol-id', '/dev/vdc')

        mock_host = double(name: 'host1', as_null_object: true)

        openstack.provision_storage(mock_host, mock_vm)
      end
    end

    # -------------------------------------------------------------------------
    # cleanup tests
    # -------------------------------------------------------------------------
    describe '#cleanup' do
      it 'deletes ephemeral keypairs created during provisioning' do
        openstack.instance_variable_set(:@ephemeral_keypairs, ['kp1', 'kp2'])

        fake_kp = double()
        allow(fake_kp).to receive(:destroy)

        mock_keypairs = double()
        allow(@compute_client).to receive(:key_pairs).and_return(mock_keypairs)

        allow(mock_keypairs).to receive(:get).with('kp1').and_return(fake_kp)
        allow(mock_keypairs).to receive(:get).with('kp2').and_return(fake_kp)

        expect(fake_kp).to receive(:destroy).twice

        expect { openstack.cleanup }.not_to raise_error
      end
    end
  end
end