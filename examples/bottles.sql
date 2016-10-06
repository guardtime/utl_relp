set serveroutput on;
declare
  l_relp utl_relp.relp_engine_typ;
--  l_nr pls_integer;
begin
  utl_tcp.close_all_connections;

  dbms_output.enable(10000);
  
  utl_relp.engine_enable_command(l_relp, 'syslog', true);
  utl_relp.engine_enable_command(l_relp, 'close', false);

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