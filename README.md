[![License](https://img.shields.io/:license-apache-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0.html)
[![CII Best Practices](https://bestpractices.coreinfrastructure.org/projects/73/badge)](https://bestpractices.coreinfrastructure.org/projects/73)
[![Puppet Forge](https://img.shields.io/puppetforge/v/nexus_artifact/auditd.svg)](https://forge.puppetlabs.com/nexus_artifact/auditd)
[![Puppet Forge Downloads](https://img.shields.io/puppetforge/dt/nexus_artifact/auditd.svg)](https://forge.puppetlabs.com/nexus_artifact/auditd)
[![Build Status](https://travis-ci.org/nexus_artifact/pupmod-nexus_artifact-auditd.svg)](https://travis-ci.org/nexus_artifact/pupmod-nexus_artifact-auditd)

# nexus_artifact

#### Table of Contents

<!-- vim-markdown-toc GFM -->

* [Description](#description)
  * [Beginning with nexus_artifact](#beginning-with-nexus_artifact)
* [Usage](#usage)
  * [Ensure that the artifact is present](#ensure-that-the-artifact-is-present)
  * [Ensure that the artifact is the latest version](#ensure-that-the-artifact-is-the-latest-version)
  * [Ensure that the artifact is a specific version](#ensure-that-the-artifact-is-a-specific-version)
* [Limitations](#limitations)
* [Development](#development)
  * [Acceptance tests](#acceptance-tests)

<!-- vim-markdown-toc -->

## Description

This module provides a native puppet type for downloading artifacts from a
Sonatype Nexus 3+ server.

Care was taken to keep as many of the capabilities as possible in pure Ruby for
maximum portabilty.

HTTPS is used where possible but may be disabled if required.

Extended file metadata is used if possible to record relevant details to
make version and checksum comparisons faster during future asset comparisons.

See [REFERENCE.md](./REFERENCE.md) for full API details.

### Beginning with nexus_artifact

## Usage

Basic usage is quite simple.

### Ensure that the artifact is present

```puppet
nexus_artifact { '/tmp/thor.gem':
  server     => 'my.server.com',
  repository => 'Rubygems',
  artifact   => 'thor'
}
```

### Ensure that the artifact is the latest version

```puppet
nexus_artifact { '/tmp/thor.gem':
  ensure     => 'latest',
  server     => 'my.server.com',
  repository => 'Rubygems',
  artifact   => 'thor'
}
```

### Ensure that the artifact is a specific version

```puppet
nexus_artifact { '/tmp/thor.gem':
  ensure     => '1.0.1',
  server     => 'my.server.com',
  repository => 'Rubygems',
  artifact   => 'thor'
}
```

## Limitations

Currently, the module does not support writing extended file metadata on Windows.

## Development

Please read our [Contribution Guide](https://simp.readthedocs.io/en/stable/contributors_guide/Contribution_Procedure.html)

### Acceptance tests

This module includes [Beaker](https://github.com/puppetlabs/beaker) acceptance
tests using the SIMP [Beaker Helpers](https://github.com/simp/rubygem-simp-beaker-helpers).
By default the tests use [Vagrant](https://www.vagrantup.com/) with
[VirtualBox](https://www.virtualbox.org) as a back-end; Vagrant and VirtualBox
must both be installed to run these tests without modification. To execute the
tests run the following:

```shell
bundle exec rake beaker:suites
```

Some environment variables may be useful:

```shell
BEAKER_debug=true
BEAKER_provision=no
BEAKER_destroy=no
BEAKER_use_fixtures_dir_for_modules=yes
BEAKER_fips=yes
```

* `BEAKER_debug`: show the commands being run on the STU and their output.
* `BEAKER_destroy=no`: prevent the machine destruction after the tests finish so you can inspect the state.
* `BEAKER_provision=no`: prevent the machine from being recreated. This can save a lot of time while you're writing the tests.
* `BEAKER_use_fixtures_dir_for_modules=yes`: cause all module dependencies to be loaded from the `spec/fixtures/modules` directory, based on the contents of `.fixtures.yml`.  The contents of this directory are usually populated by `bundle exec rake spec_prep`.  This can be used to run acceptance tests to run on isolated networks.
* `BEAKER_fips=yes`: enable FIPS-mode on the virtual instances. This can
  take a very long time, because it must enable FIPS in the kernel
  command-line, rebuild the initramfs, then reboot.

Please refer to the [SIMP Beaker Helpers documentation](https://github.com/simp/rubygem-simp-beaker-helpers/blob/master/README.md)
for more information.
