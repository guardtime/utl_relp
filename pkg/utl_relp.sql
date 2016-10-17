create or replace package &&target..utl_relp is
 /*
 * Copyright 2013-2016 Guardtime, Inc.
 *
 * This file is part of the Guardtime UTL_RELP package.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 * You may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *     http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES, CONDITIONS, OR OTHER LICENSES OF ANY KIND, either
 * express or implied. See the License for the specific language governing
 * permissions and limitations under the License.
 * "Guardtime" and "KSI" are trademarks or registered trademarks of
 * Guardtime, Inc., and no license to trademarks is granted; Guardtime
 * reserves and retains all trademark rights.
 */
 

  /*****************************************************************************
   ** Exception: SERVER_CLOSED
   ** Description: This exception is raised when the RELP server returns an explicit
   **              message that it will close the connection.
   ****************************************************************************/
  SERVER_CLOSED exception;
  SERVER_CLOSED_CODE constant pls_integer := -20001;
  pragma exception_init ( SERVER_CLOSED, -20001);
  
  /*****************************************************************************
   ** Exception: INVALID_RESPONSE
   ** Description: This exception is raised when the RELP server returns a
   **              unexpected response. In this case it is unable to predict
   **              if the request was actually accepted by the server.
   ****************************************************************************/
  INVALID_RESPONSE exception;
  INVALID_RESPONSE_CODE constant pls_integer := -20002;
  pragma exception_init (INVALID_RESPONSE, -20002);
  
  /*****************************************************************************
   ** Exception: RELP_ERROR
   ** Description: This exception is raised when the RELP server returns an explicit
   **              error code. See SQLERRM for more details.
   ****************************************************************************/
  RELP_ERROR exception;
  RELP_ERROR_CODE constant pls_integer := -20003;
  pragma exception_init (RELP_ERROR, -20003);
  
  /*****************************************************************************
   ** Exception: CONNECTION_ERROR
   ** Description: This exception is raised when there was an error sending
   **              the request or receiving the response. See SQLERRM for more
   **              details.
   ****************************************************************************/
  CONNECTION_ERROR exception;
  CONNECTION_ERROR_CODE constant pls_integer := -20004;
  pragma exception_init (CONNECTION_ERROR, -20004);
 
  /*****************************************************************************
   ** Exception: SERVER_CLOSED
   ** Description: This exception is raised when the RELP server does not support
   **              one of the mandatory commands specified with ENGINE_ENABLE_COMMAND
   **              procedure.
   ****************************************************************************/
  COMMAND_NOT_SUPPORTED exception;
  COMMAND_NOT_SUPPORTED_CODE constant pls_integer := -20005;
  pragma exception_init (COMMAND_NOT_SUPPORTED, -20005);

  /*****************************************************************************
   ** Subtype: command_typ
   ** Description: All commands sent and received from the RELP server must fit into
   **              this subtype.
   ****************************************************************************/
  subtype command_typ is varchar2(32);

  /*****************************************************************************
   ** Type: command_status_typ
   ** Description: This type is used to track the availability of the commands
   **              requested by the user and the actual supported commands by
   **              RELP server.
   ****************************************************************************/
  type command_status_typ is record (
    /* Does the server support the command. */
    available boolean,
    
    /* Is the command mandatory. If true and the command is not supported by the
     * server, the COMMAND_NOT_SUPPORTED is raised. */
    mandatory boolean
  );
  
  /*****************************************************************************
   ** Type: command_map_typ
   ** Description: This associative array type is used to map commands with the
   **              apporpriate statuses for easy access.
   ****************************************************************************/
  type command_map_typ is table of command_status_typ index by command_typ;

  /*****************************************************************************
   ** Subtype: featurename_typ
   ** Description: The type for the feature name in the offers.
   ****************************************************************************/
  subtype featurename_typ is varchar2(320);

  /*****************************************************************************
   ** Subtype: featurename_typ
   ** Description: The type for the feature value in the offers.
   ****************************************************************************/
  subtype featurevalue_typ is varchar2(2550);
  
  /*****************************************************************************
   ** Type: feature_map_typ
   ** Description: This associative array type is used to map feature names with
   **              the apporpriate values for easy access.
   ****************************************************************************/
  type feature_map_typ is table of featurevalue_typ index by featurename_typ;
  
  /*****************************************************************************
   ** Type: relp_engine_typ
   ** Description: This is the central type for accessing the RELP service. Before it
   **              can be used, the engine must be connected using ENGINE_CONNECT
   **              procedure.
   ** Note: The engine must be destructed after use with the ENGINE_DESTRUCT
   **       procedure.
   ****************************************************************************/
  type relp_engine_typ is record (
    /* Transaction number. */
    txnr           number,
    /* Requested and actually supported methods. */
    commands       command_map_typ,
    /* Local offers sent by ENGINE_CONNECT. */
    local_offers   feature_map_typ,
    /* Offers from the RELP server. */
    remote_offers  feature_map_typ,
    /* TCP connection. */
    connection  utl_tcp.connection
  );

  /*****************************************************************************
   ** Procedure: engine_enable_command
   ** Description: Adds a new command to the offers being sent to the RELP sever.
   ** In out: p_engine    - the RELP engine.
   ** In:     p_command   - the command.
   ** In:     p_mandatory - raise an error if the RELP server does not support this.
   ****************************************************************************/
  procedure engine_enable_command(p_engine in out nocopy relp_engine_typ, p_command in command_typ, p_mandatory in boolean);

  /*****************************************************************************
   ** Procedure: engine_connect
   ** Description: Connects the engine with the RELP server.
   ** In out: p_engine      - the RELP engine.
   ** In:     p_host        - hostname.
   ** In:     p_port        - port number.
   ** In:     p_timeout     - transaction timeout in seconds. (NULL indicates to
   **                         wait forever. For more information see UTL_TCP.open_connection
   **                         function.
   ** In:     p_wallet_path - path to the Oracle wallet if TLS is used.
   ** In:     p_wallet_pass - the wallet password.
   ** Note: The engine must be destructed after use with the ENGINE_DESTRUCT
   **       procedure.
   ****************************************************************************/
  procedure engine_connect(
      p_engine      in out nocopy relp_engine_typ,
      p_host        in            varchar2,
      p_port        in            pls_integer,
      p_timeout     in            pls_integer     default null,
      p_wallet_path in            varchar2        default null, 
      p_wallet_pass in            varchar2        default null);
  
  /*****************************************************************************
   ** Procedure: write_log
   ** Description: sends a log message to the loggin server.
   ** In out: p_engine          - the RELP engine.
   ** In:     p_message         - the log message.
   ** In:     p_facility        - the facility of the log message.
   ** In:     p_severity        - the severity of the log message.
   ** In:     p_process_id      - the process id.
   ** In:     p_message_id      - the message id.
   ** In:     p_structured_data - structured data (see RFC-5424).
   ****************************************************************************/
  procedure write_log(
      p_engine in out nocopy relp_engine_typ, 
      p_message in varchar2, 
      p_facility in pls_integer default null, 
      p_severity in pls_integer default null,
      p_process_id in varchar2 default null,
      p_message_id in varchar2 default null,
      p_structured_data in varchar2 default null);

  /*****************************************************************************
   ** Procedure: engine_destruct
   ** Description: ends the session and closes the tcp connection.
   ** In out: p_engine - the RELP engine.
   ****************************************************************************/
  procedure engine_destruct(p_engine in out nocopy relp_engine_typ);
end utl_relp;
/

