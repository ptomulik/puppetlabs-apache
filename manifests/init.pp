# Class: apache
#
# This class installs Apache
#
# Parameters:
#
# Actions:
#   - Install Apache
#   - Manage Apache service
#
# Requires:
#
# Sample Usage:
#
class apache (
  $apache_service       = $apache::params::apache_service,
  $default_mods         = true,
  $default_vhost        = true,
  $default_confd_files  = true,
  $default_ssl_vhost    = false,
  $default_ssl_cert     = $apache::params::default_ssl_cert,
  $default_ssl_key      = $apache::params::default_ssl_key,
  $default_ssl_chain    = undef,
  $default_ssl_ca       = undef,
  $default_ssl_crl_path = undef,
  $default_ssl_crl      = undef,
  $service_enable       = true,
  $purge_configs        = true,
  $purge_vdir           = false,
  $serveradmin          = 'root@localhost',
  $sendfile             = false,
  $error_documents      = false,
  $httpd_dir            = $apache::params::httpd_dir,
  $confd_dir            = $apache::params::confd_dir,
  $vhost_dir            = $apache::params::vhost_dir,
  $vhost_enable_dir     = $apache::params::vhost_enable_dir,
  $mod_dir              = $apache::params::mod_dir,
  $mod_enable_dir       = $apache::params::mod_enable_dir,
  $mpm_module           = $apache::params::mpm_module,
  $conf_template        = $apache::params::conf_template,
  $servername           = $apache::params::servername,
  $server_root          = $apache::params::server_root,
  $user                 = $apache::params::user,
  $group                = $apache::params::group,
  $keepalive            = $apache::params::keepalive,
  $keepalive_timeout    = $apache::params::keepalive_timeout,
  $logroot              = $apache::params::logroot,
  $ports_file           = $apache::params::ports_file,
) inherits apache::params {

  validate_bool($default_vhost)
  validate_bool($default_confd_files)
  # true/false is sufficient for both ensure and enable
  validate_bool($service_enable)

  $valid_mpms_re = $::osfamily ? {
    'FreeBSD' => '(event|itk|peruser|prefork|worker)',
    'Debian'  => '(itk|prefork|worker)',
    default   => '(prefork|worker)'
  }

  if $mpm_module {
    validate_re($mpm_module, $valid_mpms_re)
  }

  # NOTE: on FreeBSD it's mpm module's responsibility to install httpd package.
  # NOTE: the same strategy may be introduced for other OSes. For this, you
  # should delete the 'if' block below and modify all MPM modules' manifests
  # such that they include apache::package class (currently event.pp, itk.pp,
  # peruser.pp, prefork.pp, worker.pp).
  if $::osfamily != 'FreeBSD' {
    package { 'httpd':
      ensure => present,
      name   => $apache::params::apache_name,
      notify => Class['Apache::Service'],
    }
  }

  # declare the web server user and group
  # Note: requiring the package means the package ought to create them and not puppet
  group { $group:
    ensure  => present,
    require => Package['httpd']
  }

  user { $user:
    ensure  => present,
    gid     => $group,
    require => Package['httpd'],
  }

  class { 'apache::service':
    service_name   => $apache_service,
    service_enable => $service_enable,
  }

  # Deprecated backwards-compatibility
  if $purge_vdir {
    warning('Class[\'apache\'] parameter purge_vdir is deprecated in favor of purge_configs')
    $purge_confd = $purge_vdir
  } else {
    $purge_confd = $purge_configs
  }

  Exec {
    path => '/bin:/sbin:/usr/bin:/usr/sbin',
  }

  exec { "mkdir ${confd_dir}":
    creates => $confd_dir,
    require => Package['httpd'],
  }
  file { $confd_dir:
    ensure  => directory,
    recurse => true,
    purge   => $purge_confd,
    notify  => Class['Apache::Service'],
    require => Package['httpd'],
  }

  if ! defined(File[$mod_dir]) {
    exec { "mkdir ${mod_dir}":
      creates => $mod_dir,
      require => Package['httpd'],
    }
    file { $mod_dir:
      ensure  => directory,
      recurse => true,
      purge   => $purge_configs,
      notify  => Class['Apache::Service'],
      require => Package['httpd'],
    }
  }

  if $mod_enable_dir and ! defined(File[$mod_enable_dir]) {
    $mod_load_dir = $mod_enable_dir
    exec { "mkdir ${mod_enable_dir}":
      creates => $mod_enable_dir,
      require => Package['httpd'],
    }
    file { $mod_enable_dir:
      ensure  => directory,
      recurse => true,
      purge   => $purge_configs,
      notify  => Class['Apache::Service'],
      require => Package['httpd'],
    }
  } else {
    $mod_load_dir = $mod_dir
  }

  if ! defined(File[$vhost_dir]) {
    exec { "mkdir ${vhost_dir}":
      creates => $vhost_dir,
      require => Package['httpd'],
    }
    file { $vhost_dir:
      ensure  => directory,
      recurse => true,
      purge   => $purge_configs,
      notify  => Class['Apache::Service'],
      require => Package['httpd'],
    }
  }

  if $vhost_enable_dir and ! defined(File[$vhost_enable_dir]) {
    $vhost_load_dir = $vhost_enable_dir
    exec { "mkdir ${vhost_load_dir}":
      creates => $vhost_load_dir,
      require => Package['httpd'],
    }
    file { $vhost_enable_dir:
      ensure  => directory,
      recurse => true,
      purge   => $purge_configs,
      notify  => Class['Apache::Service'],
      require => Package['httpd'],
    }
  } else {
    $vhost_load_dir = $vhost_dir
  }

  concat { $ports_file:
    owner   => 'root',
    group   => $apache::params::root_group,
    mode    => '0644',
    notify  => Class['Apache::Service'],
    require => Package['httpd'],
  }
  concat::fragment { 'Apache ports header':
    target  => $ports_file,
    content => template('apache/ports_header.erb')
  }

  if $apache::params::conf_dir and $apache::params::conf_file {
    case $::osfamily {
      'debian': {
        $docroot              = '/var/www'
        $pidfile              = '${APACHE_PID_FILE}'
        $error_log            = 'error.log'
        $error_documents_path = '/usr/share/apache2/error'
        $scriptalias          = '/usr/lib/cgi-bin'
        $access_log_file      = 'access.log'
      }
      'redhat': {
        $docroot              = '/var/www/html'
        $pidfile              = 'run/httpd.pid'
        $error_log            = 'error_log'
        $error_documents_path = '/var/www/error'
        $scriptalias          = '/var/www/cgi-bin'
        $access_log_file      = 'access_log'
      }
      'freebsd': {
        $docroot              = '/usr/local/www/apache22/data'
        $pidfile              = '/var/run/httpd.pid'
        $error_log            = 'httpd-error.log'
        $error_documents_path = '/usr/local/www/apache22/error'
        $scriptalias          = '/usr/local/www/apache22/cgi-bin'
        $access_log_file      = 'httpd-access.log'
      }
      default: {
        fail("Unsupported osfamily ${::osfamily}")
      }
    }
    $freebsd_workarounds = $::osfamily ? {
      'freebsd' => true,
      default   => false
    }
    # Template uses:
    # - $pidfile
    # - $user
    # - $group
    # - $logroot
    # - $error_log
    # - $sendfile
    # - $mod_dir
    # - $ports_file
    # - $confd_dir
    # - $vhost_dir
    # - $error_documents
    # - $error_documents_path
    # - $freebsd_workarounds
    # - $keepalive
    # - $keepalive_timeout
    # - $server_root
    file { "${apache::params::conf_dir}/${apache::params::conf_file}":
      ensure  => file,
      content => template($conf_template),
      notify  => Class['Apache::Service'],
      require => Package['httpd'],
    }

    # preserve back-wards compatibility to the times when default_mods was
    # only a boolean value. Now it can be an array (too)
    if is_array($default_mods) {
      class { 'apache::default_mods':
        all  => false,
        mods => $default_mods,
      }
    } else {
      class { 'apache::default_mods':
        all => $default_mods,
      }
    }
    class { 'apache::default_confd_files':
      all => $default_confd_files
    }
    if $mpm_module {
      class { "apache::mod::${mpm_module}": }
    }
    if $default_vhost {
      apache::vhost { 'default':
        port            => 80,
        docroot         => $docroot,
        scriptalias     => $scriptalias,
        serveradmin     => $serveradmin,
        access_log_file => $access_log_file,
        priority        => '15',
      }
    }
    $ssl_access_log_file = $::osfamily ? {
      'freebsd' => $access_log_file,
      default   => "ssl_${access_log_file}",
    }
    if $default_ssl_vhost {
      apache::vhost { 'default-ssl':
        port            => 443,
        ssl             => true,
        docroot         => $docroot,
        scriptalias     => $scriptalias,
        serveradmin     => $serveradmin,
        access_log_file => $ssl_access_log_file,
        priority        => '15',
      }
    }
  }
}
