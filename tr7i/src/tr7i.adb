--  tr7i -- interactive interpreter and script runner.
--
--  This is the trusted boundary: all console and file I/O lives here, and the
--  verified core only ever sees strings and output buffers.  It is therefore
--  deliberately outside SPARK, unlike the tr7 crate.

with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Tr7.Engine; use Tr7.Engine;
with Tr7.Runtime; use Tr7.Runtime;
with Tr7.Values; use Tr7.Values;

procedure Tr7i with SPARK_Mode => Off is

   Max_Source : constant := 1_000_000;
   Max_Line   : constant := 4_096;

   E : Engine;
   Ok : Boolean;

   procedure Emit_Line (S : String) is
      Last : Natural := S'Last;
   begin
      --  GNAT's Text_IO adds a final newline at program exit when the last
      --  character written was a bare LF.  Strip a trailing LF and always
      --  terminate with New_Line so script output is exact.
      if S'Length > 0 and then S (S'Last) = LF then
         Last := S'Last - 1;
      end if;
      if S'Length > 0 and then Last >= S'First then
         Put (S (S'First .. Last));
      end if;
      New_Line;
   end Emit_Line;

   procedure Show_Result (Status : Error_Code; V : Value) is
      POk : Boolean;
   begin
      if Status = No_Error then
         if not (V.Kind = Kind_Unspecified or else V.Kind = Kind_Void) then
            Print_Value (E, V, False, POk);
            if not POk then
               Put_Line ("error: could not print result");
            end if;
         end if;
         Emit_Line (Output_Text (E));
         Reset_Output (E);
      else
         --  Evaluation stopped on an error, but whatever the program printed
         --  before it did happen and must not be thrown away.
         if Output_Text (E)'Length > 0 then
            Emit_Line (Output_Text (E));
            Reset_Output (E);
         end if;
         Put_Line ("error: " & Error_Name (Status));
      end if;
   end Show_Result;

   procedure Run_String (Source : String) is
      V : Value;
      S : Error_Code;
   begin
      Reset_Output (E);
      Evaluate (E, Source, V, S);
      Show_Result (S, V);
   end Run_String;

   procedure Run_File (Path : String) is
      F     : File_Type;
      Buf   : String (1 .. Max_Source);
      Len   : Natural := 0;
      Line  : String (1 .. Max_Line);
      Last  : Natural;
   begin
      begin
         Open (F, In_File, Path);
      exception
         when others =>
            Put_Line ("error: cannot open " & Path);
            return;
      end;

      begin
         while not End_Of_File (F) loop
            Get_Line (F, Line, Last);
            if Len + Last + 1 > Max_Source then
               Close (F);
               Put_Line ("error: file too large");
               return;
            end if;
            if Last > 0 then
               Buf (Len + 1 .. Len + Last) := Line (1 .. Last);
               Len := Len + Last;
            end if;
            if not End_Of_File (F) then
               Len := Len + 1;
               Buf (Len) := LF;
            end if;
         end loop;
         Close (F);
      exception
         when others =>
            if Is_Open (F) then
               Close (F);
            end if;
            Put_Line ("error: cannot read " & Path);
            return;
      end;

      if Len = 0 then
         return;
      end if;
      Run_String (Buf (1 .. Len));
   end Run_File;

   Line : String (1 .. Max_Line);
   Last : Natural;
   V    : Value;
   S    : Error_Code;

begin
   Initialize (E, Ok);
   if not Ok then
      Put_Line ("error: cannot initialize interpreter");
      return;
   end if;

   if Ada.Command_Line.Argument_Count > 0 then
      Run_File (Ada.Command_Line.Argument (1));
      return;
   end if;

   loop
      Put ("> ");
      begin
         Get_Line (Line, Last);
      exception
         when End_Error =>
            New_Line;
            exit;
      end;

      if Last = 0 then
         Reset_Output (E);
      else
         Reset_Output (E);
         Evaluate (E, Line (1 .. Last), V, S);
         Show_Result (S, V);
      end if;
   end loop;
end Tr7i;
