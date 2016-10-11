create or replace package body &&target..utl_relp is
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
 
  type message_typ is record (
    txnr pls_integer,
    command command_typ(200),
    payload raw(32000)
  );

  lf constant varchar2(1) := chr(10);
  sp constant varchar2(1) := chr(32);
  
  procedure close_finally(p_engine in out nocopy relp_engine_typ) is
  begin
    utl_tcp.close_connection(p_engine.connection);
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
  
  function write_command(
      p_engine in out nocopy relp_engine_typ, 
      p_command in            varchar2, 
      p_payload in            varchar2) return message_typ is
    l_command raw(32000);
    l_payload raw(32000); 
    l_bytes   pls_integer;
    l_resp    message_typ;
    l_lock    integer;
  begin
    l_payload := utl_raw.cast_to_raw(convert(p_payload, 'UTF8'));
    
    l_command := utl_raw.cast_to_raw(convert(p_engine.txnr || sp || p_command || sp || utl_raw.length(l_payload) || sp, 'UTF8'));
    l_command := utl_raw.concat(l_command, l_payload);
    l_command := utl_raw.concat(l_command, utl_raw.cast_to_raw(chr(10)));
        
    begin
      l_bytes := utl_tcp.write_raw(p_engine.connection, l_command);
      utl_tcp.flush(p_engine.connection);
    exception
      when others then
        raise_application_error(CONNECTION_ERROR_CODE, 'Unable to send log message: ' || dbms_utility.format_error_backtrace || ', ' || sqlerrm);
    end;

    -- Read the response from the server.
    l_resp := read_response(p_engine.connection);
    
    -- Check if the server is hanging up - serverclose with message id 0 is sent when the
    -- server is not happy with the request.
    if l_resp.txnr = 0 and l_resp.command = 'serverclose' then
      raise_application_error(SERVER_CLOSED_CODE, 'Server closed connection.');
    end if;
    
    -- Make sure the server is responding with rsp command and the message numbers match.
    if l_resp.txnr != p_engine.txnr or l_resp.command != 'rsp' then
      raise_application_error(INVALID_RESPONSE_CODE, 'Unexpected server response.');
    end if;
    
    -- Check for the response code.
    if utl_raw.cast_to_varchar2(l_resp.payload) not like '200 OK%' then
      raise_application_error(RELP_ERROR_CODE, 'Error from server, closing connection: "' || utl_raw.cast_to_varchar2(l_resp.payload) || '"');
    end if;
    
    p_engine.txnr := p_engine.txnr + 1;
    
    return l_resp;
  end write_command;

  procedure engine_enable_command(
      p_engine    in out nocopy relp_engine_typ, 
      p_command   in            command_typ, 
      p_mandatory in            boolean) is
    l_status command_status_typ;
  begin
    l_status.mandatory := p_mandatory;
    l_status.available := false; -- Will change this if the server responds with it.
    p_engine.commands(p_command) := l_status;
  end engine_enable_command;

  function parse_offers(p_payload in varchar2) return feature_map_typ is
    l_map feature_map_typ;
    l_name featurename_typ;
    l_value featurevalue_typ;
    l_pos pls_integer;
    l_byte raw(1);
    l_line varchar2(32000);
  begin 
    l_pos := 1;
    
    loop
      -- Start from the second line, as the first one will be 200 OK.
      l_pos := l_pos + 1;
    
      l_line := regexp_substr(p_payload, '[^' || lf || ']+', 1, l_pos);
      exit when l_line is null;
      
      l_name := regexp_substr(l_line, '[^=]+', 1, 1);
      l_value := substr(l_line, length(l_name) + 2);
      
      l_map(l_name) := l_value;
    end loop;
    
    return l_map;
  end parse_offers;
  
  function serialize_offers(p_offers in feature_map_typ) return varchar2 is
    l_feature featurename_typ;
    l_result  varchar2(32000) := '';
  begin
    l_feature := p_offers.first;
    while l_feature is not null loop
      if length(l_result) > 0 then
        l_result := l_result || lf;
      end if;
      
      l_result := l_result || l_feature || '=' || p_offers(l_feature);
      
      l_feature := p_offers.next(l_feature);
    end loop;
    
    return l_result;
  end serialize_offers;

  procedure engine_connect(
      p_engine      in out nocopy relp_engine_typ,
      p_host        in            varchar2,
      p_port        in            pls_integer,
      p_wallet_path in            varchar2        default null, 
      p_wallet_pass in            varchar2        default null) is
    l_offers  varchar2(32000);
    l_command command_typ;
    l_payload varchar2(32000) := '';
    l_resp    message_typ;
  begin
    --close_finally(p_engine);
    
    p_engine.connection := utl_tcp.open_connection(
        remote_host => p_host, 
        remote_port => p_port, 
        charset => 'UTF8',
        wallet_path => p_wallet_path,
        wallet_password => p_wallet_pass);
        
    if p_wallet_path is not null or p_wallet_pass is not null then
      utl_tcp.secure_connection(p_engine.connection);
    end if;
    
    -- Just in case check if the user has added manually some commands.
    if p_engine.local_offers.exists('commands') then
      l_offers := p_engine.local_offers('commands');
    elsif p_engine.commands.first is null then
      declare
        l_status command_status_typ;
      begin
        l_status.mandatory := false;
        l_status.available := false;
        p_engine.commands('syslog') := l_status;
      end;
    end if;
    
    l_command := p_engine.commands.first;
    
    while l_command is not null loop
      if l_offers is not null then
        l_offers := l_offers || ',' || l_command;
      else
        l_offers := l_command;
      end if;
      l_command := p_engine.commands.next(l_command);
    end loop;
    
    -- Always reset the counter.
    p_engine.txnr := 1;
    
    p_engine.local_offers('relp_version') := '1';
    p_engine.local_offers('commands') := l_offers;
        
    l_resp := write_command(p_engine, 'open', serialize_offers(p_engine.local_offers));
    
    declare
      l_command featurename_typ;
      l_pos pls_integer;
      l_offer_status command_status_typ;
    begin
      -- Parse the response and update the supported commands.
      p_engine.remote_offers := parse_offers(utl_raw.cast_to_varchar2(l_resp.payload));
      
      -- Loop over all the commands.
      if p_engine.remote_offers.exists('commands') then
        l_pos := 0;
        loop
          l_pos := l_pos + 1;
          l_command := regexp_substr(p_engine.remote_offers('commands'), '[^,]+', 1, l_pos);
          
          exit when l_command is null;
                    
          if p_engine.commands.exists(l_command) then
            p_engine.commands(l_command).available := true;
          else
            l_offer_status.mandatory := false;
            l_offer_status.available := true;
            p_engine.commands(l_command) := l_offer_status;
          end if;
        end loop;
      end if;

      -- Loop over all the offers and raise an error if a mandatory offer is missing.
      if p_engine.commands.first is not null then
        l_command := p_engine.commands.first;
        loop
          exit when l_command is null;
          
          if p_engine.commands(l_command).mandatory and not p_engine.commands(l_command).available then
            raise_application_error(COMMAND_NOT_SUPPORTED_CODE, 'Mandatory command "' || l_command || '" not supported by the server.');
          end if;
          
          l_command := p_engine.commands.next(l_command);

        end loop;
      end if;
    end;
    
    
  end engine_connect;
  
  procedure write_log(
      p_engine in out nocopy relp_engine_typ, 
      p_message in varchar2, 
      p_facility in pls_integer default null, 
      p_severity in pls_integer default null,
      p_process_id in varchar2 default null,
      p_message_id in varchar2 default null,
      p_structured_data in varchar2 default null) is
    l_header   varchar2(32000) := '';
    l_hostname varchar2(32000) := '';
    l_resp     message_typ;
  begin
    begin
      l_hostname := UTL_INADDR.get_host_name;
    exception
      when others
        then null;
    end;
  
    l_header := l_header || '<' || ( nvl(p_facility, 16) * 8 + nvl(p_severity, 6)) || '>'; /* Priority. */
    l_header := l_header || '1 '; /* Version. */
    l_header := l_header || to_char(systimestamp,'YYYY-MM-DD') || 'T' || to_char(systimestamp,'HH24:MI:SS.FF') || regexp_replace(dbtimezone, '^+00:00$', 'Z') ||' '; /* Timestamp. */
    l_header := l_header || nvl(l_hostname, '-') || ' '; /* Hostname. */
    l_header := l_header || nvl(sys_context('userenv','db_name'), '-') || ' '; /* App-name. */
    l_header := l_header || nvl(p_process_id, '-') || ' '; /* Process id. */
    l_header := l_header || nvl(p_message_id, '-') || ' '; /* Message id. */
    l_header := l_header || nvl(p_structured_data, '-') || ' '; /* Structured data. */

    l_resp := write_command(p_engine, 'syslog', l_header || p_message);
  end write_log;
  
  procedure engine_destruct(p_engine in out nocopy relp_engine_typ) is
  begin
    -- Try to send a polite close message.
    declare
      l_resp message_typ;
    begin
      l_resp := write_command(p_engine, 'close', null);
    exception
      when SERVER_CLOSED then
        null;
      when others then
        null; -- What else can we do?
    end;
    utl_tcp.close_connection(p_engine.connection);
  exception 
    when others then
      -- TODO: Find out if we should raise some exceptions here.
      null; -- Still nothing to do.
  end engine_destruct;
end utl_relp;
