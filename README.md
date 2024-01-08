# beaker-openstack

[![License](https://img.shields.io/github/license/voxpupuli/beaker-openstack.svg)](https://github.com/voxpupuli/beaker-openstack/blob/master/LICENSE)
[![Test](https://github.com/voxpupuli/beaker-openstack/actions/workflows/test.yml/badge.svg)](https://github.com/voxpupuli/beaker-openstack/actions/workflows/test.yml)
[![Release](https://github.com/voxpupuli/beaker-openstack/actions/workflows/release.yml/badge.svg)](https://github.com/voxpupuli/beaker-openstack/actions/workflows/release.yml)
[![RubyGem Version](https://img.shields.io/gem/v/beaker-openstack.svg)](https://rubygems.org/gems/beaker-openstack)
[![RubyGem Downloads](https://img.shields.io/gem/dt/beaker-openstack.svg)](https://rubygems.org/gems/beaker-openstack)
[![Donated by Puppet Inc](https://img.shields.io/badge/donated%20by-Puppet%20Inc-fb7047.svg)](#transfer-notice)

Beaker library to use openstack hypervisor

# How to use this wizardry

This gem that allows you to use hosts with [openstack](openstack.md) hypervisor with [beaker](https://github.com/puppetlabs/beaker). 

Beaker will automatically load the appropriate hypervisors for any given hosts file, so as long as your project dependencies are satisfied there's nothing else to do. No need to `require` this library in your tests.

## With Beaker 3.x

This library is included as a dependency of Beaker 3.x versions, so there's nothing to do.

## With Beaker 4.x

As of Beaker 4.0, all hypervisor and DSL extension libraries have been removed and are no longer dependencies. In order to use a specific hypervisor or DSL extension library in your project, you will need to include them alongside Beaker in your Gemfile or project.gemspec. E.g.

~~~ruby
# Gemfile
gem 'beaker', '~>4.0'
gem 'beaker-aws'
# project.gemspec
s.add_runtime_dependency 'beaker', '~>4.0'
s.add_runtime_dependency 'beaker-aws'
~~~

# Spec tests

Spec test live under the `spec` folder. There are the default rake task and therefore can run with a simple command:
```bash
bundle exec rake test:spec
```

# Acceptance tests

We run beaker's base acceptance tests with this library to see if the hypervisor is working with beaker. Please check our [openstack docs](openstack.md) to create host file to run acceptance tests. You need to set two environment variables before running acceptance tests:

1. `OPENSTACK_HOSTS` - Path to hostfile with hosts using openstack hypervisor

2. `OPENSTACK_KEY` - Path to private key that is used to SSH into Openstack VMs 

You will need at least two hosts defined in a nodeset file. An example comprehensive nodeset is below (note that not all parameters are required):

```yaml

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
  openstack_volume_support: <true/false>
  security_group: ['default']
  preserve_hosts: <always/onfail/onpass/never>
  create_in_parallel: true
  run_in_parallel: ['configure', 'install']
  type: <foss/git/pe>
```

Note that when using _id parameters, you must also match the parameter type across the following when domain is specified:
- openstack_project_id
- openstack_user_domain_id
- openstack_project_domain_id 

Further, you can opt to use a static master by setting the master's hypervisor to none, and identifying its location thus:
```yaml
    hypervisor: none
    hostname: <master_hostname>
    vmhostname: <master_hostname>
    ip: <master_ip>
```

Additionally, you can set instance creation to occur in parallel instead of sequentially via this CONFIG entry:
```
create_in_parallel: true

Additional parameter information is available at https://github.com/voxpupuli/beaker/blob/master/docs/concepts/argument_processing_and_precedence.md

There is a simple rake task to invoke acceptance test for the library once the two environment variables are set:
```bash
bundle exec rake test:acceptance
```

# Contributing

Please refer to puppetlabs/beaker's [contributing](https://github.com/puppetlabs/beaker/blob/master/CONTRIBUTING.md) guide.
