{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.openldap;
  openldap = pkgs.openldap;

  configFile = pkgs.writeText "slapd.conf" cfg.extraConfig;
  configLDIF = pkgs.writeText "slapd-init.ldif" cfg.extraLDIF;

in

{

  ###### interface

  options = {

    services.openldap = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = "
          Whether to enable the ldap server.
        ";
      };

      user = mkOption {
        type = types.string;
        default = "openldap";
        description = "User account under which slapd runs.";
      };

      group = mkOption {
        type = types.string;
        default = "openldap";
        description = "Group account under which slapd runs.";
      };

      urlList = mkOption {
        type = types.listOf types.string;
        default = [ "ldap:///" ];
        description = "URL list slapd should listen on.";
        example = [ "ldaps:///" ];
      };

      dataDir = mkOption {
        type = types.string;
        default = "/var/db/openldap";
        description = "The database directory.";
      };

      dataDirs = mkOption {
        type = types.listOf types.string;
        default = [ ];
        description = "Additional database directories.";
      };

      configDir = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Use this optional config directory instead of using slapd.conf";
        example = "/var/db/slapd.d";
      };

      extraLDIF = mkOption {
        type = types.nullOr types.lines;
        default = "";
        description = "
          slapd configuration directory initalisation
        ";
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "
          slapd.conf configuration
        ";
        example = literalExample ''
            '''
            include ${pkgs.openldap.out}/etc/schema/core.schema
            include ${pkgs.openldap.out}/etc/schema/cosine.schema
            include ${pkgs.openldap.out}/etc/schema/inetorgperson.schema
            include ${pkgs.openldap.out}/etc/schema/nis.schema

            database bdb 
            suffix dc=example,dc=org 
            rootdn cn=admin,dc=example,dc=org 
            # NOTE: change after first start
            rootpw secret
            directory /var/db/openldap
            '''
          '';
      };
    };

  };


  ###### implementation

  config = mkIf config.services.openldap.enable {

    environment.systemPackages = [ openldap ];

    systemd.services.openldap = {
      description = "LDAP server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      preStart = ''
        mkdir -p /var/run/slapd
        chown -R ${cfg.user}:${cfg.group} /var/run/slapd
        ${builtins.foldl' (md: dataDir: md +
          ''
            mkdir -p ${dataDir} 
            chown -R ${cfg.user}:${cfg.group} ${dataDir}
          ''
        ) "" ([ cfg.dataDir ] ++ cfg.dataDirs)}
        ${if cfg.configDir != null then ''
          mkdir -p ${cfg.configDir}
          if ! test -e "${cfg.configDir}/cn=config/" ; then
            ${openldap.out}/bin/slapadd -F ${cfg.configDir} -l ${configLDIF} -n0
          fi
          chown -R ${cfg.user}:${cfg.group} ${cfg.configDir}
        '' else null}
      '';
      serviceConfig.ExecStart = "${openldap.out}/libexec/slapd -u ${cfg.user} -g ${cfg.group} -d 0 -h \"${concatStringsSep " " cfg.urlList}\" ${if cfg.configDir == null then "-f "+configFile else "-F "+cfg.configDir}";
    };

    users.extraUsers.openldap =
      { name = cfg.user;
        group = cfg.group;
        uid = config.ids.uids.openldap;
      };

    users.extraGroups.openldap =
      { name = cfg.group;
        gid = config.ids.gids.openldap;
      };

  };
}
