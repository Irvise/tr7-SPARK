with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Interfaces; use Interfaces;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Pairs; use Tr7.Pairs;
with Tr7.Reader;

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
      if N = 0 then
         Put (B, '0', Ok);
         return;
      end if;
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

   --  Print a non-negative value.  Bytes and counts have no sign to handle,
   --  which is the point: routed through Put_Integer their arguments made the
   --  sign branches statically dead, and GNAT said so at every call site.
   procedure Put_Nat
     (N  : Natural;
      B  : in out Output_Buffer;
      Ok : in out Boolean)
   is
      Dec_Chars : constant String := "0123456789";
      Rest      : Natural := N;
      Buf       : String (1 .. 10) := (others => '0');
      Len       : Natural range 0 .. 10 := 0;
   begin
      if N = 0 then
         Put (B, '0', Ok);
         return;
      end if;

      while Len < 10 and then Rest > 0 loop
         Len := Len + 1;
         Buf (Len) := Dec_Chars (Integer (Rest mod 10) + 1);
         Rest := Rest / 10;
      end loop;

      for I in reverse 1 .. Len loop
         Put (B, Buf (I), Ok);
         if not Ok then
            return;
         end if;
      end loop;
   end Put_Nat;

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

   --  One character at the end of the buffer.  Capacity is checked here, at
   --  the single point where the cursor moves, so every caller's increment
   --  question has one answer; the fixed bounds below make it unreachable.
   procedure Append_Char
     (S : in out String;
      K : in out Natural;
      C : Character)
     with
       Pre  => S'First = 1 and then K <= S'Length,
       Post => K <= S'Length
   is
   begin
      if K >= S'Length then
         return;
      end if;
      K := K + 1;
      S (K) := C;
   end Append_Char;

   --  Format a positive finite value with P significant digits, %g style:
   --  fixed notation while the exponent suits (-4 <= exp < P), scientific
   --  otherwise, trailing zeros stripped but one digit always kept after the
   --  point so the result reads back as a flonum.  The rounding is on the
   --  remainder after the P-th digit.
   procedure Format_G
     (X   : Long_Float;
      P   : Positive;
      S   : out String;
      Len : out Natural)
     with
       Pre  => S'First = 1
         and then S'Length >= 48
         and then X > 0.0
         and then P <= 17,
       Post => Len <= S'Length
   is
      M      : Long_Float := X;
      Exp    : Integer range -400 .. 400 := 0;
      --  Started full: only the first N_Dig entries are ever read, but flow
      --  analysis cannot follow writes through a computed index.
      Digs   : String (1 .. 17) := (others => '0');
      N_Dig  : Natural range 0 .. 17 := 0;
      D      : Natural range 0 .. 9;
      K      : Natural := 0;
      Last   : Natural range 0 .. 17;
      Carry  : Boolean;
      AE     : Natural range 0 .. 400;
   begin
      S := (others => ' ');

      --  Scale into [1, 10).  A finite double needs at most 309 steps; the
      --  guards are the prover's answer, and are unreachable in practice.
      while M >= 10.0 loop
         pragma Loop_Invariant (M >= 0.0);
         pragma Loop_Invariant (M <= Long_Float'Last);
         exit when Exp = 400;
         M := M / 10.0;
         Exp := Exp + 1;
      end loop;
      while M < 1.0 loop
         pragma Loop_Invariant (M >= 0.0);
         pragma Loop_Invariant (M <= 10.0);
         exit when Exp = -400;
         M := M * 10.0;
         Exp := Exp - 1;
      end loop;
      if M >= 10.0 and then Exp < 400 then
         --  Rounding can land exactly on 10.0; step back once.
         M := M / 10.0;
         Exp := Exp + 1;
      end if;

      --  P digits, each taken by counting units (no float-to-integer
      --  conversion, hence no range check hanging off an unanalyzed result).
      --  The scaling above leaves M below ten; the clamp is unreachable and
      --  exists so the loop's entry bound is a path fact rather than a
      --  chain of floating-point steps the provers do not finish.
      if M > 10.0 then
         M := 5.0;
      end if;
      while N_Dig < P loop
         pragma Loop_Invariant (M >= 0.0);
         pragma Loop_Invariant (M <= 10.0);
         D := 0;
         while M >= 1.0 and then D < 9 loop
            pragma Loop_Invariant (M >= 0.0);
            pragma Loop_Invariant (M <= 10.0);
            M := M - 1.0;
            D := D + 1;
         end loop;
         --  Nine units came out of a value under ten, so the remainder is
         --  below one; the clamp turns that into a path fact for the shift
         --  below (and is unreachable, so it never changes a digit).
         if M >= 1.0 then
            M := 0.5;
         end if;
         N_Dig := N_Dig + 1;
         Digs (N_Dig) := Character'Val (Character'Pos ('0') + D);
         --  M is already the remainder (the loop above counted whole units
         --  out of it), so this is just the shift to the next place.
         M := M * 10.0;
      end loop;

      --  Round on what remains.
      if M >= 5.0 then
         Carry := True;
         for I in reverse 1 .. N_Dig loop
            exit when not Carry;
            if Digs (I) = '9' then
               Digs (I) := '0';
            elsif Digs (I) < '9' then
               Digs (I) := Character'Val (Character'Pos (Digs (I)) + 1);
               Carry := False;
            end if;
         end loop;
         if Carry then
            --  Every digit was a 9: the value gained a place, so 9.99 with
            --  two digits becomes 1.00 and the exponent steps up.
            Digs (1) := '1';
            for I in 2 .. N_Dig loop
               Digs (I) := '0';
            end loop;
            if Exp < 400 then
               Exp := Exp + 1;
            end if;
         end if;
      end if;

      if Exp >= -4 and then Exp < P then
         if Exp >= 0 then
            for I in 1 .. Exp + 1 loop
               pragma Loop_Invariant (K <= S'Length);
               Append_Char (S, K, Digs (I));
            end loop;
            if Exp + 1 >= N_Dig then
               Append_Char (S, K, '.');
               Append_Char (S, K, '0');
            else
               Last := Exp + 1;
               for I in Exp + 2 .. N_Dig loop
                  if Digs (I) /= '0' then
                     Last := I;
                  end if;
               end loop;
               Append_Char (S, K, '.');
               for I in Exp + 2 .. Last loop
               pragma Loop_Invariant (K <= S'Length);
                  Append_Char (S, K, Digs (I));
               end loop;
               if Last = Exp + 1 then
                  Append_Char (S, K, '0');
               end if;
            end if;
         else
            Append_Char (S, K, '0');
            Append_Char (S, K, '.');
            --  0.5 has its first digit in the tenths place: -Exp - 1 zeros.
            for I in 1 .. (-Exp - 1) loop
               pragma Loop_Invariant (K <= S'Length);
               Append_Char (S, K, '0');
            end loop;
            Last := 0;
            for I in 1 .. N_Dig loop
               if Digs (I) /= '0' then
                  Last := I;
               end if;
            end loop;
            if Last = 0 then
               Append_Char (S, K, '0');
            else
               for I in 1 .. Last loop
               pragma Loop_Invariant (K <= S'Length);
                  Append_Char (S, K, Digs (I));
               end loop;
            end if;
         end if;
      else
         Append_Char (S, K, Digs (1));
         Append_Char (S, K, '.');
         if N_Dig = 1 then
            Append_Char (S, K, '0');
         else
            Last := 1;
            for I in 2 .. N_Dig loop
               if Digs (I) /= '0' then
                  Last := I;
               end if;
            end loop;
            for I in 2 .. Last loop
               pragma Loop_Invariant (K <= S'Length);
               Append_Char (S, K, Digs (I));
            end loop;
            if Last = 1 then
               Append_Char (S, K, '0');
            end if;
         end if;
         Append_Char (S, K, 'e');
         if Exp < 0 then
            Append_Char (S, K, '-');
            AE := -Exp;
         else
            Append_Char (S, K, '+');
            AE := Exp;
         end if;
         --  At least two exponent digits, more when needed.
         if AE >= 100 then
            Append_Char
              (S, K, Character'Val (Character'Pos ('0') + AE / 100));
         end if;
         Append_Char
           (S, K, Character'Val (Character'Pos ('0') + (AE / 10) mod 10));
         Append_Char
           (S, K, Character'Val (Character'Pos ('0') + AE mod 10));
      end if;

      Len := K;
   end Format_G;

   --  Write a flonum so that reading it back gives the same value: try
   --  increasing precision until the reader agrees, then fall back to the
   --  full 17 digits (correct decimal, and round-trips by construction of
   --  IEEE doubles).
   procedure Put_Float
     (X  : Long_Float;
      B  : in out Output_Buffer;
      Ok : in out Boolean)
   is
      S    : String (1 .. 64);
      Len  : Natural;
      Y    : Long_Float;
      Is_F : Boolean;
      Good : Boolean;
      Mag  : Long_Float;
   begin
      if not Ok then
         return;
      end if;
      if X /= X then
         Put (B, "+nan.0", Ok);
         return;
      end if;
      if X > Long_Float'Last then
         Put (B, "+inf.0", Ok);
         return;
      end if;
      if X < -Long_Float'Last then
         Put (B, "-inf.0", Ok);
         return;
      end if;
      if X = 0.0 then
         --  The sign of a negative zero is not kept (v1): both print as 0.0.
         Put (B, "0.0", Ok);
         return;
      end if;

      if X < 0.0 then
         Put (B, '-', Ok);
         Mag := -X;
      else
         Mag := X;
      end if;

      for P in 1 .. 16 loop
         Format_G (Mag, P, S, Len);
         Tr7.Reader.Parse_Float (S (1 .. Len), Is_F, Y, Good);
         if Good and then Is_F and then Y = Mag then
            Put (B, S (1 .. Len), Ok);
            return;
         end if;
      end loop;
      Format_G (Mag, 17, S, Len);
      Put (B, S (1 .. Len), Ok);
   end Put_Float;

   --  A symbol is printed raw only when it is in the reader's ordinary
   --  symbol alphabet; otherwise it is bar-quoted, which the reader now
   --  understands.  The empty symbol and numeric-looking names must be
   --  quoted or they read back as something else.
   function Is_Symbol_Char (C : Character) return Boolean is
     (C in 'a' .. 'z' or else C in 'A' .. 'Z' or else C in '0' .. '9'
      or else C = '!' or else C = '$' or else C = '%' or else C = '&'
      or else C = '*' or else C = '+' or else C = '-' or else C = '.'
      or else C = '/' or else C = ':' or else C = '<' or else C = '='
      or else C = '>' or else C = '?' or else C = '@' or else C = '^'
      or else C = '_' or else C = '~');

   function Is_Simple_Symbol (C : Cell) return Boolean is
      Name : constant String := Text_Of (C);
   begin
      if Name'Length = 0 then
         return False;
      end if;
      --  Names that could read as a number, or as a sign/dot prefix of one,
      --  must be bar-quoted.  Bare +, -, . and ... remain valid symbols.
      if Name (Name'First) in '0' .. '9' then
         return False;
      end if;
      if Name'Length >= 2
        and then (Name (Name'First) = '+' or else Name (Name'First) = '-'
                  or else Name (Name'First) = '.')
        and then (Name (Name'First + 1) in '0' .. '9'
                  or else Name (Name'First + 1) = '.')
      then
         return False;
      end if;
      for I in Name'Range loop
         if not Is_Symbol_Char (Name (I)) then
            return False;
         end if;
      end loop;
      return True;
   end Is_Simple_Symbol;

   procedure Put_Escaped_Char
     (B  : in out Output_Buffer;
      C  : Character;
      Ok : in out Boolean)
   is
      Code : constant Natural := Character'Pos (C);
   begin
      if C = '"' then
         Put (B, '\', Ok);
         Put (B, '"', Ok);
      elsif C = '\' then
         Put (B, '\', Ok);
         Put (B, '\', Ok);
      elsif C = LF then
         Put (B, '\', Ok);
         Put (B, 'n', Ok);
      elsif C = HT then
         Put (B, '\', Ok);
         Put (B, 't', Ok);
      elsif C = CR then
         Put (B, '\', Ok);
         Put (B, 'r', Ok);
      elsif Code < 32 or else Code = 127 then
         Put (B, '\', Ok);
         Put (B, 'x', Ok);
         Put_Hex (B, Unsigned_32 (Code), Ok);
         Put (B, ';', Ok);
      else
         Put (B, C, Ok);
      end if;
   end Put_Escaped_Char;

   procedure Put_Symbol (B : in out Output_Buffer; C : Cell; Ok : in out Boolean)
   is
      Name : constant String := Text_Of (C);
   begin
      if Is_Simple_Symbol (C) then
         Put (B, Name, Ok);
         return;
      end if;
      Put (B, '|', Ok);
      for I in Name'Range loop
         if Name (I) = '|' or else Name (I) = '\' then
            Put (B, '\', Ok);
         end if;
         Put (B, Name (I), Ok);
         if not Ok then
            return;
         end if;
      end loop;
      Put (B, '|', Ok);
   end Put_Symbol;

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

         when Kind_EOF =>
            Put (B, "#<eof>", Ok);

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

         when Kind_Flonum =>
            Put_Float (V.F, B, Ok);

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
                     Put_Symbol (B, C, Ok);

                  when Cell_String =>
                     if Display then
                        Put (B, Text_Of (C), Ok);
                     else
                        Put (B, '"', Ok);
                        for I in 1 .. C.Name_Len loop
                           pragma Loop_Invariant (Ok = Ok'Loop_Entry);
                           Put_Escaped_Char (B, C.Name (I), Ok);
                           if not Ok then
                              return;
                           end if;
                        end loop;
                        Put (B, '"', Ok);
                     end if;

                  when Cell_Vector =>
                     Put (B, "#(", Ok);
                     if not Ok then
                        return;
                     end if;
                     declare
                        Cur   : Value := C.Car;
                        Item  : Value;
                        Node  : Cell;
                        Node_Ok : Boolean;
                        First : Boolean := True;
                     begin
                        loop
                           exit when Is_Nil (Cur);
                           if not Is_Handle (Cur) then
                              Ok := False;
                              return;
                           end if;
                           Fetch (H, To_Handle (Cur), Node, Node_Ok);
                           if not Node_Ok or else Node.Kind /= Cell_Pair then
                              Ok := False;
                              return;
                           end if;
                           if not First then
                              Put (B, ' ', Ok);
                              if not Ok then
                                 return;
                              end if;
                           end if;
                           First := False;
                           Item := Node.Car;
                           Write_Internal (H, Item, B, Node_Ok, Depth - 1,
                                           Display);
                           Ok := Node_Ok;
                           if not Ok then
                              return;
                           end if;
                           Cur := Node.Cdr;
                        end loop;
                     end;
                     Put (B, ')', Ok);

                  when Cell_Bytevector =>
                     Put (B, "#u8(", Ok);
                     if not Ok then
                        return;
                     end if;
                     for I in 1 .. C.Name_Len loop
                        if I > 1 then
                           Put (B, ' ', Ok);
                           if not Ok then
                              return;
                           end if;
                        end if;
                        Put_Nat (Natural (Character'Pos (C.Name (I))), B, Ok);
                        if not Ok then
                           return;
                        end if;
                     end loop;
                     Put (B, ')', Ok);

                  when Cell_Input_Port =>
                     Put (B, "#<input-port>", Ok);

                  when Cell_Output_Port =>
                     Put (B, "#<output-port>", Ok);

                  when Cell_Values =>
                     Put (B, "#<values>", Ok);

                  when Cell_Closure =>
                     Put (B, "#<procedure>", Ok);

                  when Cell_Primitive =>
                     Put (B, "#<primitive>", Ok);

                  when Cell_Environment =>
                     Put (B, "#<environment>", Ok);

                  when Cell_Macro =>
                     Put_String (B, "#<macro>", Ok);

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
