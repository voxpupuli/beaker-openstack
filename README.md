# beaker-openstack

[![License](https://img.shields.io/github/license/voxpupuli/beaker-openstack.svg)](https://github.com/voxpupuli/beaker-openstack/blob/master/LICENSE)
[![Test](https://github.com/voxpupuli/beaker-openstack/actions/workflows/test.yml/badge.svg)](https://github.com/voxpupuli/beaker-openstack/actions/workflows/test.yml)
[![Release](https://github.com/voxpupuli/beaker-openstack/actions/workflows/release.yml/badge.svg)](https://github.com/voxpupuli/beaker-openstack/actions/workflows/release.yml)
[![RubyGem Version](https://img.shields.io/gem/v/beaker-openstack.svg)](https://rubygems.org/gems/beaker-openstack)
[![RubyGem Downloads](https://img.shields.io/gem/dt/beaker-openstack.svg)](https://rubygems.org/gems/beaker-openstack)
[![Donated by Puppet Inc](https://img.shields.io/badge/donated%20by-Puppet%20Inc-fb7047.svg)](#transfer-notice)

Beaker hypervisor support for provisioning hosts on OpenStack clouds.

This version of beaker-openstack has been fully modernized and now supports:

- Keystone v3 authentication (v2 removed)
- Neutron networking only (Nova-network removed)
- Deterministic floating IP allocation
- Boot-from-volume provisioning
- Optional additional Cinder volumes
- Updated keypair lifecycle management
- Stronger credential validation and error reporting
- Predictable provisioning and teardown behavior
- Updated RSpec suite and acceptance test flow

---------------------------------------------------------------------

# Overview

beaker-openstack provides an OpenStack hypervisor implementation for Beaker.
It provisions OpenStack instances, assigns floating IPs, manages keypairs, and optionally provisions volumes.

Beaker automatically loads hypervisors based on the `hypervisor:` field in your nodeset.
No explicit require is needed.

---------------------------------------------------------------------

# Compatibility

## Beaker 3.x
Beaker 3.x included hypervisors directly.
This gem remains compatible, but Beaker 3 is no longer maintained.

## Beaker 4.x and later
Beaker 4.x removed all bundled hypervisors.
You must include this gem explicitly:

Gemfile:
```
gem 'beaker', '~> 4.0'
gem 'beaker-openstack', '~> 3.0'
```
---------------------------------------------------------------------

# Installation

Add to your Gemfile or gemspec: `gem 'beaker-openstack'`

Then install: `bundle install`

---------------------------------------------------------------------

# Configuration

All OpenStack configuration is provided under the `CONFIG:` section of your nodeset.

Required parameters:
```
- openstack_auth_url
- openstack_username
- openstack_api_key
- openstack_project_name
- openstack_network
```

Optional parameters:
```
- openstack_keyname
- security_group
- openstack_floating_ip
- floating_ip_pool
- openstack_volume_support
- openstack_region
- openstack_project_id
- openstack_user_domain
- openstack_user_domain_id
- openstack_project_domain
- openstack_project_domain_id
- preserve_hosts
- create_in_parallel
- run_in_parallel
- timeout
```

Notes:

- When using `_id` parameters, ensure all three IDs match the parameter type:
```
openstack_project_id
openstack_user_domain_id
openstack_project_domain_id
```

- Static master nodes can be defined with:
```
hypervisor: none
hostname: <master_hostname>
vmhostname: <master_hostname>
ip: <master_ip>
```

- Additionally, you can set instance creation to occur in parallel instead of sequentially via this CONFIG entry:
`create_in_parallel: true`

- For parameter precedence, see: [Beaker argument processing](https://github.com/voxpupuli/beaker/blob/master/docs/concepts/argument_processing_and_precedence.md)

---------------------------------------------------------------------

# Nodeset Examples

You will need at least two hosts defined in a nodeset file. An example comprehensive nodeset is below (note that not all parameters are required):
```
HOSTS:
  master:
    roles:
      - agent
      - master
      - dashboard
      - database
    hypervisor: openstack
    platform: <my_platform> 
    user: <host_username>
    image: <host_image>
    flavor: <host_flavor>
    ssh:
      user: cloud-user
      password: <cloud-user_password>
      auth_methods:
        - password
        - publickey
      keys:
        - <relative_path/public_key>
    user_data: |
      #cloud-config
      output: {all: '| tee -a /var/log/cloud-init-output.log'}
      disable_root: <True/False>
      ssh_pwauth: <True/False>
      chpasswd:
        list: |
           root:<root_password>
           cloud-user:<cloud-user_password>
        expire: False
      runcmd:
        - <my_optional_commands>

  agent_1:
    roles:
      - agent
      - default
    hypervisor: openstack
    platform: <my_platform>
    user: <host_username>
    image: <host_image>
    flavor: <host_flavor>
    ssh:
      user: cloud-user
      password: <cloud-user_password>
      auth_methods:
        - publickey
      keys:
        - <relative_path/public_key>
      number_of_password_prompts: 0
      keepalive: true
      keepalive_interval: 5
    user_data: |
      #cloud-config
      output: {all: '| tee -a /var/log/cloud-init-output.log'}
      disable_root: <True/False>
      ssh_pwauth: <True/False>
      chpasswd:
        list: |
           root:<root_password>
           cloud-user:<cloud-user_password>
        expire: False
      runcmd:
        - <my_optional_commands>

CONFIG:
  log_level: <trace/debug/verbose/info/notify/warn>
  trace_limit: 50
  timesync: <true/false>
  nfs_server: none
  consoleport: 443
  openstack_username: <insert_username>
  openstack_api_key: <insert_password>
#  openstack_project_name: <insert_project_name>     # alternatively use openstack_project_id
  openstack_project_id: <insert_id>
#  openstack_user_domain: <insert user_domain>       # alternatively use openstack_user_domain_id
  openstack_user_domain_id: <insert_id>
#  openstack_project_domain: <insert_project_domain> # alternatively use openstack_project_domain_id
  openstack_project_domain_id: <insert_id>
  openstack_auth_url: http://<keystone_ip>:5000/v3/
  openstack_network: <insert_network>
  openstack_keyname: <insert_key>
  openstack_floating_ip: <true/false>
  floating_ip_pool: <insert_network or uuid>
  openstack_volume_support: <true/false>
  security_group: ['default']
  preserve_hosts: <always/onfail/onpass/never>
  create_in_parallel: true
  run_in_parallel: ['configure', 'install']
  type: <foss/git/pe>
```

Boot-from-volume example:
```
HOSTS:
  agent_1:
    roles:
      - agent
    hypervisor: openstack
    image: <host_image>
    flavor: <host_flavor>
    root_volume:
      size: <size in Gb>
      delete_on_termination: <true/false>
```

Additional volumes example:
```
HOSTS:
  agent_2:
    roles:
      - agent
    hypervisor: openstack
    image: <host_image>
    flavor: <host_flavor>
    root_volume:
      size: <size in Gb>
      delete_on_termination: <true/false>
    volumes:
      data1:
        size: <size in Gb>
        description: second-volume
```

Notes:
- `root_volume` replaces ephemeral disk.
- `volumes` are attached after instance is ACTIVE.
- `volume_size` defaults to image minimum unless overridden.
- `Floating IPs` are allocated deterministically if enabled.

---------------------------------------------------------------------

# Volume Provisioning
- Instance boots from Cinder volume instead of ephemeral disk if root_volume is set.
- Volume size can be overridden via volume_size.
- The volume size defaults to the image minimum size unless overridden by volume_size (in Gb).
- Additional volumes are created after the instance becomes ACTIVE.
---------------------------------------------------------------------

# Floating IP Allocation
- Managed via Neutron.
- If `openstack_floating_ip: true`, a floating IP is created.
- IP is attached to instance's primary port.
- Allocation is deterministic and logged clearly

---------------------------------------------------------------------

# Spec Tests

RSpec tests live under spec/.
Run them with:
`bundle exec rake test:spec`

The spec suite includes:
- Credential validation
- Keypair lifecycle
- Volume provisioning logic
- Floating IP allocation
- Error handling and retries

---------------------------------------------------------------------

# Acceptance Tests

Acceptance tests require:
- `OPENSTACK_HOSTS` - path to a nodeset using the OpenStack hypervisor
- `OPENSTACK_KEY` - path to the private SSH key used for the instances

Run acceptance tests:
```
bundle exec rake test:acceptance
```

At least one host must use the OpenStack hypervisor.

---------------------------------------------------------------------

# Troubleshooting

## Authentication failures:
Ensure all three Keystone v3 IDs are correct:
- `openstack_project_id`
- `openstack_user_domain_id`
- `openstack_project_domain_id`

## Floating IP not assigned:
Check:
- Neutron external network exists
- Security groups allow SSH ingress

## Volume creation errors:
Verify:
- Cinder backend is available
- Volume type exists (if specified)

SSH timeouts:
Use:
```
ssh:
  keepalive: true
  keepalive_interval: 5
```
---------------------------------------------------------------------

# Contributing

Contributions are welcome.
Please follow the Beaker project’s contribution guidelines:
https://github.com/voxpupuli/.github/blob/master/CONTRIBUTING.md
