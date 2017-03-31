# UTL\_RELP #

This package to use RELP (Reliable Event Logging Protocol) from Oracle PL/SQL.

## Installation ##

For the installation the target schema RELP\_SCHEMA (can be an arbitrary existing schema) needs to have EXECUTE grant on the UTL\_TCP package.

To install the package execute the install.sql script with the target schema as its first parameter.

	SQL> spool utl_relp.log
    SQL> @install.sql RELP_SCHEMA
	SQL> spool off

The target schema RELP\_SCHEMA needs to be added to the ACL with:

 * RESOLVE privilege on localhost (to be able to determine the hostname - this is sent witch each log message to the rsyslog server - see [RFC5424](https://tools.ietf.org/html/rfc5424)).
 * RESOLVE and CONNECT to the remote host where the logs are sent to.

```
    BEGIN
    
      -- Configuration for the RELP service.
      DBMS_NETWORK_ACL_ADMIN.CREATE_ACL(
          acl => 'relp_remote.xml', 
          description => 'ACL for UTL_RELP', 
          principal => 'RELP_SCHEMA', 
          is_grant => true, 
          privilege => 'connect');
    
      DBMS_NETWORK_ACL_ADMIN.ADD_PRIVILEGE(
          acl => 'relp_remote.xml', 
          principal => 'RELP_SCHEMA', 
          is_grant => true, 
          privilege => 'resolve');
    
      DBMS_NETWORK_ACL_ADMIN.ASSIGN_ACL(
          acl => 'relp_remote.xml', 
          host => 'log.remote.host.name'); 
    
      -- Configuration to get the local hostname.
      DBMS_NETWORK_ACL_ADMIN.CREATE_ACL(
          acl => 'relp_localhost.xml', 
          description => 'ACL for UTL_RELP', 
          principal => 'RELP_SCHEMA', 
          is_grant => true, 
          privilege => 'resolve');
    
      DBMS_NETWORK_ACL_ADMIN.ASSIGN_ACL(
          acl => 'relp_localhost.xml', 
          host => 'localhost'); 
     
      COMMIT;
    END; 
    /
```

## Usage ##

```
    declare
      l_relp utl_relp.relp_engine_typ;
    begin
      -- Connect to the relp server.
      utl_relp.engine_connect(l_relp, 'log.remote.host.name', 20514);
  
      -- Write the log message.
      utl_relp.write_log(l_relp, 'Hello RELP');
  
      -- Destruct the session.
      utl_relp.engine_destruct(l_relp);
    end;
```

## License ##

See [LICENSE](LICENSE) file.

## Dependencies ##

No external dependencies.

## Compatibility ##
| Software                    | Compatibility                                |
| :---                        | :---                                         | 
| Oracle 11g (11.2.0.4.0)     | Developed and tested using this version.     |
| rsyslog (8.16.0)            | Developed and tested using this version      |
