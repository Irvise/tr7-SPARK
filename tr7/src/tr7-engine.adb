with Tr7.Env;
with Tr7.Ids; use Tr7.Ids;
with Tr7.Primitives; use Tr7.Primitives;
with Tr7.Reader; use Tr7.Reader;
with Tr7.Writer;

package body Tr7.Engine with
   SPARK_Mode => On
is

   procedure Initialize
     (E  : out Engine;
      Ok : out Boolean)
   is
      Good   : Boolean;
      Prim_H : Handle;
      Sym    : Value;
   begin
      --  Every component of the OUT parameter is written before it can be
      --  read, on every path, including the failure paths.
      E.Output := (Data => (others => ' '), Len => 0);
      E.M := (others => <>);
      Heap.Initialize (E.H);

      Tr7.Env.New_Environment (E.H, Null_Handle, E.Global, Good);
      if not Good then
         Ok := False;
         return;
      end if;

      for P in Primitive_Id loop
         if P /= P_None then
            New_Primitive (E.H, P, Prim_H, Good);
            if not Good then
               Ok := False;
               return;
            end if;
            Intern (E.H, Name_Of (P), Sym, Good);
            if not Good then
               Ok := False;
               return;
            end if;
            Tr7.Env.Define (E.H, E.Global, Sym, From_Handle (Prim_H), Good);
            if not Good then
               Ok := False;
               return;
            end if;
         end if;
      end loop;

      Ok := True;
   end Initialize;

   procedure Evaluate
     (E      : in out Engine;
      Source : String;
      Result : out Value;
      Status : out Error_Code)
   is
      Pos    : Natural := 0;
      Expr   : Value;
      RS     : Read_Status;
      Old_Pos : Natural;
   begin
      Result := Unspecified_Value;
      Status := No_Error;

      loop
         pragma Loop_Invariant (Pos <= Source'Length);
         pragma Loop_Invariant (E.H.Ready);
         Old_Pos := Pos;
         Read_Datum (E.H, Source, Pos, Expr, RS);
         case RS is
            when Read_End =>
               return;

            when Read_Error =>
               Status := Error_Parse;
               return;

            when Read_Ok =>
               if Pos = Old_Pos then
                  Status := Error_Parse;
                  return;
               end if;
               Tr7.Machine.Evaluate (E.H, E.Global, Expr, E.M, E.Output);
               if E.M.Error /= No_Error then
                  Status := E.M.Error;
                  return;
               end if;
               Result := E.M.Result;
         end case;
      end loop;
   end Evaluate;

   procedure Print_Value
     (E       : in out Engine;
      V       : Value;
      Display : Boolean;
      Ok      : out Boolean)
   is
   begin
      Tr7.Writer.Write_Value (E.H, V, E.Output, Ok, Display);
   end Print_Value;

   procedure Reset_Output (E : in out Engine) is
   begin
      Tr7.Runtime.Reset_Output (E.Output);
   end Reset_Output;

   function Output_Text (E : Engine) return String is
      (String (E.Output.Data (1 .. E.Output.Len)));

end Tr7.Engine;
