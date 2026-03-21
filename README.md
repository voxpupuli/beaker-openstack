# beaker-openstack

[![License](https://img.shields.io/github/license/voxpupuli/beaker-openstack.svg)](https://github.com/voxpupuli/beaker-openstack/blob/master/LICENSE)
[![Test](https://github.com/voxpupuli/beaker-openstack/actions/workflows/test.yml/badge.svg)](https://github.com/voxpupuli/beaker-openstack/actions/workflows/test.yml)
[![Release](https://github.com/voxpupuli/beaker-openstack/actions/workflows/release.yml/badge.svg)](https://github.com/voxpupuli/beaker-openstack/actions/workflows/release.yml)
[![RubyGem Version](https://img.shields.io/gem/v/beaker-openstack.svg)](https://rubygems.org/gems/beaker-openstack)
[![RubyGem Downloads](https://img.shields.io/gem/dt/beaker-openstack.svg)](https://rubygems.org/gems/beaker-openstack)
[![Donated by Puppet Inc](https://img.shields.io/badge/donated%20by-Puppet%20Inc-fb7047.svg)](#transfer-notice)

Beaker hypervisor support for provisioning hosts on modern OpenStack clouds.

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

Beaker automatically loads hypervisors based on the "hypervisor:" field in your nodeset.
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

Add to your Gemfile or gemspec:
`gem 'beaker-openstack'`
Then install:
`bundle install`

---------------------------------------------------------------------

# Configuration

All OpenStack configuration is provided under the `CONFIG:` section of your nodeset.

Required parameters:
```
- openstack_auth_url
- openstack_username
- openstack_api_key
- openstack_project_id
- openstack_user_domain_id
- openstack_project_domain_id
- openstack_network
- openstack_keyname
```

Optional parameters:
```
- openstack_floating_ip
- openstack_volume_support
- openstack_volume_size
- openstack_additional_volumes
- security_group
- preserve_hosts
- create_in_parallel
- run_in_parallel
```

Notes:

- When using _id parameters, ensure all three IDs match the parameter type:
```
openstack_project_id
openstack_user_domain_id
openstack_project_domain_id
```
- Static master nodes can be defined with `hypervisor: none` and providing `hostname`, `vmhostname`, and `ip`.
- For parameter precedence, see: [Beaker argument processing](https://github.com/voxpupuli/beaker/blob/master/docs/concepts/argument_processing_and_precedence.md)

---------------------------------------------------------------------

# Nodeset Examples

Minimal example:
```
HOSTS:
  agent:
    roles:
      - agent
    hypervisor: openstack
    platform: el-9-x86_64
    image: rhel-9-latest
    flavor: m1.medium
    ssh:
      user: cloud-user

CONFIG:
  openstack_username: myuser
  openstack_api_key: mypass
  openstack_project_id: 1234567890abcdef
  openstack_user_domain_id: default
  openstack_project_domain_id: default
  openstack_auth_url: https://keystone.example.com:5000/v3
  openstack_network: private-net
  openstack_keyname: beaker-key
  openstack_floating_ip: true
  preserve_hosts: onfail
  create_in_parallel: true
  run_in_parallel: ['configure', 'install']
```

Boot-from-volume example:
```
HOSTS:
  master:
    roles:
      - master
    hypervisor: openstack
    image: rhel-9-latest
    flavor: m1.large
    root_volume:
      size: 20
      delete_on_termination: true
    ssh:
      user: cloud-user

CONFIG:
  openstack_volume_support: true
```

Additional volumes example:
```
HOSTS:
  db:
    roles:
      - database
    hypervisor: openstack
    image: ubuntu-22.04
    flavor: m1.large
    root_volume:
      size: 20
      delete_on_termination: false
    volumes:
      data1:
        size: 20
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
- If `openstack_floating_ip: true`, a floating IP is created or reused.
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
- `OPENSTACK_HOSTS` — path to a nodeset using the OpenStack hypervisor
- `OPENSTACK_KEY` — path to the private SSH key used for the instances

Run acceptance tests:
```
bundle exec rake test:acceptance
```

At least one host must use the OpenStack hypervisor.

---------------------------------------------------------------------

# Troubleshooting

##Authentication failures:
Ensure all three Keystone v3 IDs are correct:
- `openstack_project_id`
- `openstack_user_domain_id`
- `openstack_project_domain_id`

##Floating IP not assigned:
Check:
- Neutron external network exists
- Security groups allow SSH ingress

##Volume creation errors:
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
https://github.com/puppetlabs/beaker/blob/master/CONTRIBUTING.md
