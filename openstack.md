# Openstack

OpenStack is a free and open-source software platform for cloud computing.
[Their Site](http://www.openstack.org/)

# Getting Started

### Requirements

Get OpenStack access & security credentials:

- `openstack_api_key`
- `openstack_auth_url`
- `openstack_username`
- `openstack_project_name`
- `openstack_network`
- `openstack_keyname`

If you are using [OpenStack Dashboard "Horizon"](https://wiki.openstack.org/wiki/Horizon), you can find these values in the following places:

1. Login to Horizon / "Project" / "Compute" / "Access & Security" / "API Access" / "Download OpenStack RC File":
   - `openstack_auth_url` = `OS_AUTH_URL` (ensure it ends with `/v3`)
   - `openstack_username` = `OS_USERNAME`
   - `openstack_project_name` = `OS_PROJECT_NAME`
2. `openstack_network`: "Project" / "Network" / "Networks"
3. `openstack_keyname`: "Project" / "Compute" / "Access & Security" / "Key Pairs"
4. `openstack_api_key`: Your user password

---

### Setup an OpenStack Hosts File

An OpenStack hosts file looks like a typical Beaker hosts file, but includes additional required properties.

**Basic Openstack hosts file**
```
    HOSTS:
      centos-9-master:
        roles:
          - master
          - agent
          - database
          - dashboard
        platform: el-9-x86_64
        hypervisor: openstack
        image: centos-9-x86_64-nocm
        flavor: m1.large

    CONFIG:
      nfs_server: none
      consoleport: 443
      openstack_api_key: Pas$w0rd
      openstack_username: user
      openstack_auth_url: http://10.10.10.10:5000/v3
      openstack_project_name: testing
      openstack_user_domain: Default
      openstack_project_domain: Default
      openstack_network: testing
      openstack_floating_ip: true
      floating_ip_pool: external_network_name
```

The `image` - image name.

The `flavor` - templates for VMs, defining sizes for RAM, disk, number of cores, and so on.


# Openstack-Specific Hosts File Settings

### user-data

"user data" - a blob of data that the user can specify when they launch an instance. The instance can access this data through the metadata service or config drive with one of the next requests:

- curl http://169.254.169.254/2009-04-04/user-data
- curl http://169.254.169.254/openstack/2012-08-10/user_data


Examples of `user_data` you can find here: http://cloudinit.readthedocs.io/en/latest/topics/examples.html

Also if you plan use `user-data` make sure that 'cloud-init' package installed in your VM `image` and 'cloud-init' service is running.

**Example Openstack hosts file with user_data**
```
    HOSTS:
      centos-9-master:
        roles:
          - master
          - agent
          - database
          - dashboard
        platform: el-9-x86_64
        image: centos-9-x86_64-nocm
        flavor: m1.large
        hypervisor: openstack
        user_data: |
          #cloud-config
          bootcmd:
            - echo 123 > /tmp/test.txt
    CONFIG:
      nfs_server: none
      consoleport: 443
      openstack_api_key: Pas$w0rd
      openstack_username: user
      openstack_auth_url: http://10.10.10.10:5000/v3
      openstack_project_name: testing
      openstack_user_domain: Default
      openstack_project_domain: Default
      openstack_network: testing
      openstack_floating_ip: true
      floating_ip_pool: external_network_name
```
### Security groups

A security group is a set of rules for incoming and outgoing traffic to an instance.  You can associate a host with one or many security groups in the `CONFIG` section of your hosts file:

    `security_group: ['my_sg', 'default']`

This is an optional config parameter.

### Floating IPs

Floating IPs provide external access to instances.

```
openstack_floating_ip: true
floating_ip_pool: 'my_pool_name'
```

**Important behaviour:**

- Instances will have **two IPs**:
  - Internal (fixed) IP from the project network
  - External Floating IP (NAT mapped)
- This is **expected OpenStack behaviour**
- Beaker will use the **floating IP for connectivity**

**Requirement:**
- `floating_ip_pool` must reference an **external network**

### Volumes

Volumes are provisioned via Cinder.

To attach volumes, define a `volumes` hash under a host.  The value is a hash with a single integer parameter 'size' which defines the volume size in GB.

**Example OpenStack hosts file with non-ephemeral root volume and additional volumes**
```
    HOSTS:
      ceph:
        roles:
          - master
        hypervisor: openstack
        platform: ubuntu-16.04-amd64
        user: ubuntu
        flavor: m1.large
        image: xenial-server-cloudimg-amd64-scsi
        root_volume:
          size: 30
          delete_on_termination: true
        volumes:
          osd0:
            size: 10000
          osd1:
            size: 10000
          osd2:
            size: 10000
          journal:
            size: 1000
```

### Behaviour

- Root volume:
  - Created from image
  - Controlled by `delete_on_termination` (default: `true`)
- Additional volumes:
  - Created and attached
  - **Never deleted automatically**
  - Must be cleaned up manually if required

## Disabling Volume Support

If your OpenStack deployment does not support Cinder:

`openstack_volume_support: false`

You can also configure this setting via an environment variable:

`export OS_VOLUME_SUPPORT=false`


## Notes

- Keystone v3 is required (`/v3` auth URL)
- Do not mix `_id` and non-`_id` domain/project fields
- Floating IP networks must be marked as **external**