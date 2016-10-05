create or replace package body &&target..utl_relp is
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

  type message_typ is record (
    txnr pls_integer,
    command varchar2(200),
    payload raw(32000)
  );
  g_lockhandle varchar2(200);

  procedure close_finally(p_session in out nocopy relp_session_typ) is
  begin
        utl_tcp.close_connection(p_session.connection);
  exception
    when others then
      null;
  end close_finally;
  
  function read_token(p_connection in out nocopy utl_tcp.connection) return raw is
    l_token raw(32000);
    l_byte raw(32000);
    l_len pls_integer := 0;
  begin
    begin
      loop
         l_len := l_len + utl_tcp.read_raw(p_connection, l_byte, 1, false);
         exit when utl_raw.cast_to_binary_integer(l_byte) in (10, 32);
         l_token := utl_raw.concat(l_token, l_byte);
      end loop;
    exception
      when utl_tcp.end_of_input then
        null;
    end;
    
    return l_token;
  end read_token;
  
  function read_string_token(p_connection in out nocopy utl_tcp.connection) return varchar2 is
    l_res varchar2(32000);
  begin
    return utl_raw.cast_to_varchar2(read_token(p_connection));
  end read_string_token;
  
  function read_response(p_connection in out nocopy utl_tcp.connection) return message_typ is
    l_token raw(32000);
    l_len   pls_integer;
    l_resp  message_typ;
  begin
    l_resp.txnr := to_number(read_string_token(p_connection));
    l_resp.command := read_string_token(p_connection);
    
    -- Calculate the length of the payload.
    l_len := to_number(read_string_token(p_connection));

    if l_len > 0 then
      -- Read length bytes.
      l_len := utl_tcp.read_raw(p_connection, l_token, l_len + 1);    
    
      l_resp.payload := utl_raw.substr(l_token, 1, l_len);
    end if;
    
    return l_resp;
  exception
    when others then
      raise_application_error(CONNECTION_ERROR_CODE, 'Unable to read response: ' || dbms_utility.format_error_backtrace || ', ' || sqlerrm);
  end read_response;
  
  procedure write_command(p_session in out nocopy relp_session_typ, p_command in varchar2, p_payload in varchar2) is
    l_command raw(32000);
    l_payload raw(32000); 
    l_bytes   pls_integer;
    l_resp    message_typ;
    l_lock    integer;
  begin
    l_payload := utl_raw.cast_to_raw(convert(p_payload, 'UTF8'));
    
    l_command := utl_raw.cast_to_raw(convert(p_session.txnr || ' ' || p_command || ' ' || utl_raw.length(l_payload) || ' ', 'UTF8'));
    l_command := utl_raw.concat(l_command, l_payload);
    l_command := utl_raw.concat(l_command, utl_raw.cast_to_raw(chr(10)));
    
    begin
      l_bytes := utl_tcp.write_raw(p_session.connection, l_command);
      utl_tcp.flush(p_session.connection);
    exception
      when others then
        raise_application_error(CONNECTION_ERROR_CODE, 'Unable to send log message: ' || dbms_utility.format_error_backtrace || ', ' || sqlerrm);
    end;

    -- Read the response from the server.
    l_resp := read_response(p_session.connection);
    
    -- Check if the server is hanging up - serverclose with message id 0 is sent when the
    -- server is not happy with the request.
    if l_resp.txnr = 0 and l_resp.command = 'serverclose' then
      raise_application_error(SERVER_CLOSED_CODE, 'Server closed connection.');
    end if;
    
    -- Make sure the server is responding with rsp command and the message numbers match.
    if l_resp.txnr != p_session.txnr or l_resp.command != 'rsp' then
      raise_application_error(INVALID_RESPONSE_CODE, 'Unexpected server response.');
    end if;
    
    -- Check for the response code.
    if utl_raw.cast_to_varchar2(l_resp.payload) not like '200 OK%' then
      raise_application_error(RELP_ERROR, 'Error from server, closing connection: "' || utl_raw.cast_to_varchar2(l_resp.payload) || '"');
    end if;
    
    p_session.txnr := p_session.txnr + 1;
  end write_command;

  function init_relp(p_host in varchar2, p_port number) return relp_session_typ is
    l_session relp_session_typ;
  begin
    l_session.host := p_host;
    l_session.port := p_port;
  
    return l_session;
  end init_relp;

  procedure set_offer(p_session in out nocopy relp_session_typ, p_offer_name in varchar2, p_offer_mandatory in boolean) is
    l_status offers_status_typ;
  begin
    l_status.mandatory := p_offer_mandatory;
    l_status.available := false; -- Will change this if the server responds with it.
    p_session.offers(p_offer_name) := l_status;
  end set_offer;

  procedure connect_relp(p_session in out nocopy relp_session_typ) is
  begin
    --close_finally(p_session);
    
    p_session.connection := utl_tcp.open_connection(remote_host => p_session.host, remote_port => p_session.port, charset => 'UTF8');
    
    -- Always reset the counter.
    p_session.txnr := 1;
    
    write_command(p_session, 'open', 'commands=syslog' || chr(10) || 'relp_version=1');
  end connect_relp;
  
  procedure write_log(p_session in out nocopy relp_session_typ, p_message in varchar2) is
  begin
    write_command(p_session, 'syslog', p_message);
  end write_log;
  
  procedure close_relp(p_session in out nocopy relp_session_typ) is
  begin
    -- Try to send a polite close message.
    begin
      write_command(p_session, 'close', null);
    exception
      when SERVER_CLOSED then
        null;
      when others then
        null; -- What else can we do?
    end;
    utl_tcp.close_connection(p_session.connection);
  exception 
    when others then
      -- TODO: Find out if we should raise some exceptions here.
      null; -- Still nothing to do.
  end close_relp;
end utl_relp;