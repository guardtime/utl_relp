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

set serveroutput on;
declare
  l_relp utl_relp.relp_engine_typ;
begin
  utl_relp.engine_enable_command(l_relp, 'syslog', true);

  utl_relp.engine_connect(l_relp, 'localhost', 20514);
  
  for l_nr in reverse 1 .. 99 loop 
    if l_nr > 1 then
      utl_relp.write_log(l_relp, l_nr || ' bottles of beer on the wall, ' || l_nr || ' bottles of beer.');
      utl_relp.write_log(l_relp, 'Take one down and pass it around, ' || (l_nr - 1) || ' bottles of beer on the wall.' );
    else
      utl_relp.write_log(l_relp, l_nr || ' bottle of beer on the wall, ' || l_nr || ' bottle of beer.');
      utl_relp.write_log(l_relp, 'Take one down and pass it around, no more bottles of beer on the wall.' );
    end if;
  end loop;

  utl_relp.write_log(l_relp, 'No more bottles of beer on the wall, no more bottles of beer. ');
  utl_relp.write_log(l_relp, 'Go to the store and buy some more, 99 bottles of beer on the wall.');
  
  utl_relp.engine_destruct(l_relp);
exception
  when others then    
    dbms_output.put_line('Error: ' || dbms_utility.format_error_backtrace || ', ' || sqlerrm);
    
        begin
      utl_relp.engine_destruct(l_relp);
    exception
      when others then null;
    end;
end;
/
