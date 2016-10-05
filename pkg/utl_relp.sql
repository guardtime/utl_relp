create or replace package &&target..utl_relp is
/*
 * GUARDTIME CONFIDENTIAL
 *
 * Copyright 2008-2016 Guardtime, Inc.
 * All Rights Reserved.
 *
 * All information contained herein is, and remains, the property
 * of Guardtime, Inc. and its suppliers, if any.
 * The intellectual and technical concepts contained herein are
 * proprietary to Guardtime, Inc. and its suppliers and may be
 * covered by U.S. and foreign patents and patents in process,
 * and/or are protected by trade secret or copyright law.
 * Dissemination of this information or reproduction of this material
 * is strictly forbidden unless prior written permission is obtained
 * from Guardtime, Inc.
 * "Guardtime" and "KSI" are trademarks or registered trademarks of
 * Guardtime, Inc., and no license to trademarks is granted; Guardtime
 * reserves and retains all trademark rights.
 */
  
  SERVER_CLOSED exception;
  SERVER_CLOSED_CODE constant pls_integer := -20001;
  pragma exception_init ( SERVER_CLOSED, -20001);
  
  INVALID_RESPONSE exception;
  INVALID_RESPONSE_CODE constant pls_integer := -20002;
  pragma exception_init (INVALID_RESPONSE, -20002);
  
  RELP_ERROR exception;
  RELP_ERROR_CODE constant pls_integer := -20003;
  pragma exception_init (RELP_ERROR, -20003);
  
  CONNECTION_ERROR exception;
  CONNECTION_ERROR_CODE constant pls_integer := -20004;
  pragma exception_init (CONNECTION_ERROR, -20004);
 
  COMMAND_NOT_SUPPORTED exception;
  COMMAND_NOT_SUPPORTED_CODE constant pls_integer := -20005;
  pragma exception_init (COMMAND_NOT_SUPPORTED, -20005);

  subtype command_typ is varchar2(32);

  type offers_status_typ is record (
    available boolean,
    mandatory boolean
  );
  
  type offer_set_typ is table of offers_status_typ index by command_typ;
  
  type relp_session_typ is record (
    txnr        number,
    host        varchar2(512),
    port        number(5),
    offers      offer_set_typ,
    connection  utl_tcp.connection
  );

  /*****************************************************************************
   ** Procedure: init_logger
   ** Description: initializes the session context for the logger.
   ** In: p_host - hostname of the RELP logging service.
   ** In: p_port - the port for the RELP logging service. 
   ****************************************************************************/
  function init_relp(p_host in varchar2, p_port number) return relp_session_typ;

  procedure set_offer(p_session in out nocopy relp_session_typ, p_offer_name in command_typ, p_offer_mandatory in boolean);

  procedure connect_relp(p_session in out nocopy relp_session_typ, p_wallet_path in varchar2 default null, p_wallet_pass in varchar2 default null);
  
  /*****************************************************************************
   ** Procedure: write_log
   ** Description: sends a log message to the loggin server.
   ** In: p_message - log message.
   ****************************************************************************/
  procedure write_log(
      p_session in out nocopy relp_session_typ, 
      p_message in varchar2, 
      p_facility in pls_integer default null, 
      p_severity in pls_integer default null,
      p_process_id in varchar2 default null,
      p_message_id in varchar2 default null,
      p_structured_data in varchar2 default null);

  /*****************************************************************************
   ** Procedure: close_logger
   ** Description: ends the session and closes the tcp connection.
   ****************************************************************************/
  procedure close_relp(p_session in out nocopy relp_session_typ);
end utl_relp;