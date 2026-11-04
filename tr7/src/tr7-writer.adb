with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Interfaces; use Interfaces;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Pairs; use Tr7.Pairs;

package body Tr7.Writer with
   SPARK_Mode => On
is


   procedure Put (B : in out Output_Buffer; C : Character; Ok : in out Boolean)
   is
      Good : Boolean;
   begin
      if not Ok then
         return;
      end if;
      Put_Char (B, C, Good);
      Ok := Good;
   end Put;

   procedure Put (B : in out Output_Buffer; S : String; Ok : in out Boolean)
     with Pre => S'First >= 1 and then S'Last < Natural'Last
   is
      Good : Boolean;
   begin
      if not Ok then
         return;
      end if;
      Put_String (B, S, Good);
      Ok := Good;
   end Put;

   --  Print N in hexadecimal, most significant digit last.
   procedure Put_Hex
     (B  : in out Output_Buffer;
      N  : Unsigned_32;
      Ok : in out Boolean)
   is
      Hex_Chars : constant String := "0123456789abcdef";
      Rest   : Unsigned_32 := N;
      --  Started full: only the first Len entries are ever printed, but flow
      --  analysis cannot follow writes through a computed index.
      Buf    : String (1 .. 8) := (others => '0');
      --  Subtype, not invariant: an Unsigned_32 needs at most eight digits, so
      --  the bound is structural and the loop needs no claim of its own.
      Len    : Natural range 0 .. 8 := 0;
   begin
      while Len < 8 and then Rest > 0 loop
         Len := Len + 1;
         Buf (Len) := Hex_Chars (Integer (Rest mod 16) + 1);
         Rest := Rest / 16;
      end loop;

      for I in reverse 1 .. Len loop
         Put (B, Buf (I), Ok);
         if not Ok then
            return;
         end if;
      end loop;
   end Put_Hex;

   procedure Put_Integer
     (N  : Integer_64;
      B  : in out Output_Buffer;
      Ok : in out Boolean)
   is
      Buf  : String (1 .. 20) := (others => '0');
      Len  : Natural := 0;
      Mag  : Integer_64;
      D    : Integer_64;
   begin
      if not Ok then
         return;
      end if;
      if N = 0 then
         Put (B, '0', Ok);
         return;
      end if;

      if N = Integer_64'First then
         Put (B, "-9223372036854775808", Ok);
         return;
      elsif N < 0 then
         Put (B, '-', Ok);
         Mag := -N;
      else
         Mag := N;
      end if;

      while Mag > 0 loop
         pragma Loop_Invariant (Len <= Buf'Length);
         if Len >= Buf'Length then
            Ok := False;
            return;
         end if;
         D := Mag mod 10;
         Len := Len + 1;
         Buf (Len) := Character'Val (Character'Pos ('0') + Integer (D));
         Mag := Mag / 10;
      end loop;

      for I in reverse 1 .. Len loop
         pragma Loop_Invariant (Ok = Ok'Loop_Entry);
         Put (B, Buf (I), Ok);
         if not Ok then
            return;
         end if;
      end loop;
   end Put_Integer;

   procedure Write_Internal
     (H       : Heap_Type;
      V       : Value;
      B       : in out Output_Buffer;
      Ok      : out Boolean;
      Depth   : Natural;
      Display : Boolean)
     with
       Pre  => H.Ready and then Depth >= 0,
       Subprogram_Variant => (Decreases => Depth);

   procedure Write_Pair
     (H       : Heap_Type;
      V       : Value;
      B       : in out Output_Buffer;
      Ok      : out Boolean;
      Depth   : Natural;
      Display : Boolean)
     with
       Pre  => H.Ready and then Depth >= 0,
       Subprogram_Variant => (Decreases => Depth)
   is
      Cur   : Value := V;
      First : Boolean := True;
      Item  : Value;
      Good  : Boolean;
      Next  : Value;
   begin
      Ok := True;
      if Depth = 0 then
         Put (B, "#<depth>", Ok);
         return;
      end if;
      Put (B, '(', Ok);
      if not Ok then
         return;
      end if;

      loop
         if Is_Nil (Cur) then
            exit;
         end if;

         if not Is_Handle (Cur) then
            Put (B, " . ", Ok);
            if Ok then
               Write_Internal (H, Cur, B, Good, Depth - 1, Display);
               Ok := Good;
            end if;
            exit;
         end if;

         declare
            Kind : Cell_Kind;
            Is_Pair : Boolean;
         begin
            Kind_Of (H, To_Handle (Cur), Kind, Is_Pair);
            if not Is_Pair or else Kind /= Cell_Pair then
               Put (B, " . ", Ok);
               if Ok then
                  Write_Internal (H, Cur, B, Good, Depth - 1, Display);
                  Ok := Good;
               end if;
               exit;
            end if;
         end;

         if not First then
            Put (B, ' ', Ok);
            if not Ok then
               return;
            end if;
         end if;

         Car_Of (H, Cur, Item, Good);
         if not Good then
            Ok := False;
            return;
         end if;
         Write_Internal (H, Item, B, Good, Depth - 1, Display);
         if not Good then
            Ok := False;
            return;
         end if;
         Cdr_Of (H, Cur, Next, Good);
         if not Good then
            Ok := False;
            return;
         end if;
         Cur := Next;
         First := False;
      end loop;

      Put (B, ')', Ok);
   end Write_Pair;

   procedure Write_Internal
     (H       : Heap_Type;
      V       : Value;
      B       : in out Output_Buffer;
      Ok      : out Boolean;
      Depth   : Natural;
      Display : Boolean)
   is
      Good : Boolean;
   begin
      Ok := True;
      if Depth = 0 then
         Put (B, "#<depth>", Ok);
         return;
      end if;

      case V.Kind is
         when Kind_Void =>
            Put (B, "#<void>", Ok);

         when Kind_Unspecified =>
            Put (B, "#<unspecified>", Ok);

         when Kind_Nil =>
            Put (B, "()", Ok);

         when Kind_Boolean =>
            if V.B then
               Put (B, "#t", Ok);
            else
               Put (B, "#f", Ok);
            end if;

         when Kind_Fixnum =>
            Put_Integer (V.N, B, Ok);

         when Kind_Character =>
            if Display then
               if V.C <= 255 then
                  Put (B, Character'Val (Integer (V.C)), Ok);
               else
                  Put (B, '?', Ok);
               end if;
            else
               Put (B, "#\", Ok);
               if V.C = Unsigned_32 (Character'Pos (' ')) then
                  Put (B, "space", Ok);
               elsif V.C = Unsigned_32 (Character'Pos (LF)) then
                  Put (B, "newline", Ok);
               elsif V.C = Unsigned_32 (Character'Pos (HT)) then
                  Put (B, "tab", Ok);
               else
                  if V.C <= 255 then
                     Put (B, Character'Val (Integer (V.C)), Ok);
                  else
                     --  Beyond the byte range: the "#\" prefix is already
                     --  out, so add the x and the digits -- that is #\x1234,
                     --  which the reader gives back as the same character.
                     Put (B, "x", Ok);
                     Put_Hex (B, V.C, Ok);
                  end if;
               end if;
            end if;

         when Kind_Handle =>
            declare
               C : Cell;
               Valid : Boolean;
            begin
               Fetch (H, V.H, C, Valid);
               if not Valid then
                  Ok := False;
                  return;
               end if;

               case C.Kind is
                  when Cell_Pair =>
                     Write_Pair (H, V, B, Good, Depth - 1, Display);
                     Ok := Good;

                  when Cell_Symbol =>
                     Put (B, Text_Of (C), Ok);

                  when Cell_String =>
                     if Display then
                        Put (B, Text_Of (C), Ok);
                     else
                        Put (B, '"', Ok);
                        for I in 1 .. C.Name_Len loop
                           pragma Loop_Invariant (Ok = Ok'Loop_Entry);
                           Put (B, C.Name (I), Ok);
                           if not Ok then
                              return;
                           end if;
                        end loop;
                        Put (B, '"', Ok);
                     end if;

                  when Cell_Closure =>
                     Put (B, "#<procedure>", Ok);

                  when Cell_Primitive =>
                     Put (B, "#<primitive>", Ok);

                  when Cell_Environment =>
                     Put (B, "#<environment>", Ok);

                  when Cell_Continuation =>
                     Put (B, "#<continuation>", Ok);

                  when Cell_Free =>
                     Ok := False;
               end case;
            end;
      end case;
   end Write_Internal;

   procedure Write_Value
     (H       : Heap_Type;
      V       : Value;
      B       : in out Output_Buffer;
      Ok      : out Boolean;
      Display : Boolean := False)
   is
   begin
      Write_Internal (H, V, B, Ok, Max_Print_Depth, Display);
   end Write_Value;

end Tr7.Writer;
