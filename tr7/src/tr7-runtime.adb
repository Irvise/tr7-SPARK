package body Tr7.Runtime with
   SPARK_Mode => On
is


   procedure Put_Char
     (B  : in out Output_Buffer;
      C  : Character;
      Ok : out Boolean)
   is
   begin
      if B.Len < Max_Output then
         B.Len := B.Len + 1;
         B.Data (B.Len) := C;
         Ok := True;
      else
         Ok := False;
      end if;
   end Put_Char;

   procedure Put_String
     (B  : in out Output_Buffer;
      S  : String;
      Ok : out Boolean)
   is
      Pos : Natural := S'First;
   begin
      if S'Length > Max_Output - B.Len then
         Ok := False;
         return;
      end if;

      for I in 1 .. S'Length loop
         pragma Loop_Invariant (B.Len = B.Len'Loop_Entry + (I - 1));
         pragma Loop_Invariant (B.Len <= Max_Output);
         pragma Loop_Invariant (Pos = S'First + (I - 1));
         pragma Loop_Invariant (Pos <= S'Last);
         B.Len := B.Len + 1;
         B.Data (B.Len) := S (Pos);
         Pos := Pos + 1;
      end loop;
      Ok := True;
   end Put_String;

   procedure Reset_Output (B : out Output_Buffer) is
   begin
      B.Data := (others => ' ');
      B.Len := 0;
   end Reset_Output;

   function Error_Name (E : Error_Code) return String is
   begin
      case E is
         when No_Error              => return "no error";
         when Error_Unbound         => return "unbound variable";
         when Error_Not_A_Procedure => return "not a procedure";
         when Error_Wrong_Arity     => return "wrong number of arguments";
         when Error_Type            => return "type error";
         when Error_Heap_Full       => return "heap exhausted";
         when Error_Parse           => return "parse error";
         when Error_Division_By_Zero => return "division by zero";
         when Error_Not_Implemented => return "not implemented";
         when Error_Step_Limit      => return "step limit exceeded";
         when Error_Malformed       => return "malformed expression";
         when Error_EOF             => return "end of input";
         when Error_Overflow        => return "exact integer overflow";
         when Error_Output_Full     => return "output buffer full";
         when Error_Index           => return "index out of range";
         when Error_Range           => return "value out of range";
      end case;
   end Error_Name;

end Tr7.Runtime;
