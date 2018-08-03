# beaker-openstack

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

You will need two hosts with same platform. A template of what hosts file is below:

```yaml
HOSTS:
  host-1:
    hypervisor: openstack
    platform: <my_platform> 
    user: <host_username>
    image: <host_image>
    roles:
      - agent
      - master
      - dashboard
      - database
      - default
  host-2:
    hypervisor: openstack
    platform: <my_platform>
    user: <host_username>
    image: <host_image>
    roles:
      - agent
CONFIG:
  nfs_server: none
  consoleport: 443
```

There is a simple rake task to invoke acceptance test for the library once the two environment variables are set:
```bash
bundle exec rake test:acceptance
```

# Contributing

Please refer to puppetlabs/beaker's [contributing](https://github.com/puppetlabs/beaker/blob/master/CONTRIBUTING.md) guide.
