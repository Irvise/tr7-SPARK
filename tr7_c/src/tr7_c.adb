with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Interfaces.C_Streams;
with System.Storage_Elements;
with Tr7.Cells;
with Tr7.Engine;
with Tr7.Env;
with Tr7.Heap;
with Tr7.Machine;
with Tr7.Pairs;
with Tr7.Runtime;
with Tr7.Reader;
with Tr7.Values;
with Tr7.Writer;

package body Tr7_C with SPARK_Mode => Off is

   --  Validity checks are off for the whole trusted body, one scoped
   --  decision with one reason: Alire's generated switches include
   --  -gnatVa (all validity checks), and under it every IEEE abnormal
   --  value -- +Inf, -Inf, NaN -- raises Constraint_Error merely by
   --  crossing a scalar parameter or a memory read.  Those values are
   --  legitimate Scheme values and legitimate C ABI traffic, and this
   --  body is the one place the header's contracts say they may appear
   --  (tr7_from_double, tr7_to_double, the nan/finite predicates).  What
   --  guards this package instead is its run-time-checked Pre/Post
   --  discipline plus the explicit checks each body performs on pointers
   --  and ranges; a compiler-inserted validity check on an IEEE double is
   --  not part of that discipline.  This mirrors the trusted-boundary
   --  rule of the project: the checks the gate polices live in tr7/src,
   --  and this package's policies are its own build's to decide.
   pragma Suppress (Validity_Check);

   --  The comparison operators of types the contracts and bodies lean on
   --  are not directly visible through a with clause alone.
   use type Interfaces.C.double;
   use type Interfaces.Unsigned_32;
   use type Tr7.Cells.Cell_Kind;
   use type Tr7.Config.Cell_Index;
   use type System.Storage_Elements.Integer_Address;
   use type Tr7.Runtime.Error_Code;
   use type Tr7.Values.Value_Kind;

   type Engine_Access is access Tr7.Engine.Engine;

   function To_Address is new Ada.Unchecked_Conversion
     (Engine_Access, System.Address);
   function To_Engine is new Ada.Unchecked_Conversion
     (System.Address, Engine_Access);
   procedure Free_Engine is new Ada.Unchecked_Deallocation
     (Tr7.Engine.Engine, Engine_Access);

   --  tr7_config_t's layout, which must match the header's struct exactly:
   --  two unsigneds then two function pointers -- 24 bytes on every LP64
   --  host, with the pointers naturally aligned at offset 8.
   type Config_Record is record
      Main_Dictionary_Size : Interfaces.C.unsigned;
      Stack_Size_Max       : Interfaces.C.unsigned;
      Malloc               : System.Address;
      Free                 : System.Address;
   end record with Convention => C;

   type Config_Access is access all Config_Record;
   function To_Config_Ptr is new Ada.Unchecked_Conversion
     (System.Address, Config_Access);

   --  libc's allocators, named so a default configuration points at the
   --  same pair upstream's does.  They are validated and never called: the
   --  arena lives in Ada's heap.
   function C_Malloc (Size : Interfaces.C.size_t) return System.Address
     with
       Import         => True,
       Convention     => C,
       External_Name  => "malloc";
   procedure C_Free (Ptr : System.Address)
     with
       Import         => True,
       Convention     => C,
       External_Name  => "free";

   function Is_Aligned (A : System.Address) return Boolean is
   begin
      return System.Storage_Elements.To_Integer (A)
               mod System.Storage_Elements.Integer_Address
                    (Tr7.Engine.Engine'Alignment) = 0;
   end Is_Aligned;

   function Is_Aligned_Config (A : System.Address) return Boolean is
   begin
      return System.Storage_Elements.To_Integer (A)
               mod System.Storage_Elements.Integer_Address
                    (Config_Record'Alignment) = 0;
   end Is_Aligned_Config;

   function Defaults_Written (Config : System.Address) return Boolean is
      C : Config_Record;
   begin
      if Config = System.Null_Address then
         return True;
      end if;
      C := To_Config_Ptr (Config).all;
      return C.Main_Dictionary_Size =
               Interfaces.C.unsigned (Tr7.Config.Max_Env_Depth)
        and then C.Stack_Size_Max =
               Interfaces.C.unsigned (Tr7.Config.Max_Stack)
        and then C.Malloc /= System.Null_Address
        and then C.Free /= System.Null_Address;
   end Defaults_Written;

   ---------------------------------------------------------------------
   --  The tr7_t encoding and the engine registry.
   --
   --  Immediates are bit-compatible with upstream because they need no
   --  pointer: a fixnum is (n << 2) | 1, the VSP constants are (k << 5) | 3
   --  and a character is (c << 5) | 11.  A double is a real tagged pointer
   --  (tag 6) to a cell this package allocates and frees with the engine,
   --  cached by bit pattern so equal doubles compare equal.  Everything
   --  the arena owns (pairs, symbols, strings, vectors, ...) is an opaque
   --  handle: (engine_id << 47) | (generation << 15) | (cell_index << 3) |
   --  tag 2.  The engine id is what every engine-less accessor resolves
   --  first, the generation is what makes a value that survived a
   --  collection -- or an engine destroy -- rejected instead of misread.
   --
   --  All of this is plain integer arithmetic over unchecked conversions;
   --  the trusted-body rule of the package covers it exactly as it covers
   --  Is_Aligned.
   ---------------------------------------------------------------------

   function To_U64 is new Ada.Unchecked_Conversion
     (Tr7_T, Interfaces.Unsigned_64);
   function From_U64 is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Tr7_T);
   function Bits_Of_Int is new Ada.Unchecked_Conversion
     (Interfaces.Integer_64, Interfaces.Unsigned_64);
   function Int_Of_Bits is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Interfaces.Integer_64);
   function Bits_Of_Float is new Ada.Unchecked_Conversion
     (Interfaces.C.double, Interfaces.Unsigned_64);
   function Address_Of_Bits is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, System.Address);
   function Bits_Of_Address is new Ada.Unchecked_Conversion
     (System.Address, Interfaces.Unsigned_64);
   function To_Chars is new Ada.Unchecked_Conversion
     (System.Address, Interfaces.C.Strings.chars_ptr);

   --  One write to the host's stdout, flushed at once: the demo mixes C's
   --  own buffered printf with these, and only a flush keeps the two in
   --  order.
   procedure Put_Out (S : String) is
      C_Str : aliased constant Interfaces.C.char_array :=
        Interfaces.C.To_C (S, Append_NUL => True);
   begin
      if Interfaces.C_Streams.fputs (C_Str'Address, Interfaces.C_Streams.stdout) < 0
      then
         null;                    --  a full stdout is the host's problem
      end if;
      if Interfaces.C_Streams.fflush (Interfaces.C_Streams.stdout) < 0 then
         null;
      end if;
   end Put_Out;

   --  The contract-support predicates of the spec: pure bit arithmetic.
   function Is_Fixnum_T (T : Tr7_T) return Boolean is
   begin
      return (To_U64 (T) and 3) = 1;
   end Is_Fixnum_T;

   function Decode_Int_Of (T : Tr7_T) return Tr7_T is
   begin
      --  Arithmetic shift: the sign of n rides in bit 63 of (n << 2) | 1
      --  exactly as upstream's TR7_TO_INT shift restores it.
      return From_U64
        (Interfaces.Shift_Right_Arithmetic (To_U64 (T), 2));
   end Decode_Int_Of;

   function Encode_Int_Bits (Value : Tr7_T) return Tr7_T is
   begin
      return From_U64
        (Interfaces.Shift_Left (To_U64 (Value), 2) or 1);
   end Encode_Int_Bits;

   function Is_Char_T (T : Tr7_T) return Boolean is
   begin
      return (To_U64 (T) and 31) = 11;
   end Is_Char_T;

   function Decode_Char_Of (T : Tr7_T) return Interfaces.Unsigned_64 is
   begin
      return Interfaces.Shift_Right (To_U64 (T), 5);
   end Decode_Char_Of;

   function Is_Double_T (T : Tr7_T) return Boolean is
   begin
      return (To_U64 (T) and 7) = 6 and then To_U64 (T) /= 0;
   end Is_Double_T;

   function Is_Heap_T (T : Tr7_T) return Boolean is
   begin
      return (To_U64 (T) and 7) = 2
        and then To_U64 (T) /= 0
        and then Interfaces.Shift_Right (To_U64 (T), 47) in 1 .. 65_535;
   end Is_Heap_T;

   function Is_Any_Value_T (T : Tr7_T) return Boolean is
   begin
      return T = Tr7_Void
        or else T = Tr7_Nil
        or else T = Tr7_False
        or else T = Tr7_True
        or else T = Tr7_Eof
        or else Is_Fixnum_T (T)
        or else Is_Char_T (T)
        or else Is_Double_T (T)
        or else Is_Heap_T (T);
   end Is_Any_Value_T;

   --  Encoding helpers.  The heap layout: 3 tag bits, 12 index bits (the
   --  arena has 4,096 cells), 32 generation bits, 16 engine-id bits -- 63
   --  bits in all, so the encoding is always a positive intptr_t.
   function Encode_Fixnum (N : Interfaces.Integer_64) return Tr7_T is
     (From_U64 (Interfaces.Shift_Left (Bits_Of_Int (N), 2) or 1));

   function Encode_Char (C : Interfaces.Unsigned_64) return Tr7_T is
     (From_U64 (Interfaces.Shift_Left (C and 16#FFFF_FFFF#, 5) or 11));

   function Encode_Heap
     (Id : Interfaces.Unsigned_32; Hd : Tr7.Values.Handle) return Tr7_T is
     (From_U64 (Interfaces.Shift_Left (Interfaces.Unsigned_64 (Id), 47)
                  or Interfaces.Shift_Left
                       (Interfaces.Unsigned_64 (Hd.Generation), 15)
                  or Interfaces.Shift_Left
                       (Interfaces.Unsigned_64 (Hd.Index), 3)
                  or 2));

   --  Encode_Double: a real tagged pointer, TR7_TAG_DOUBLE, to an 8-aligned
   --  double this package owns.  The tag arithmetic (address + 6) is what
   --  TR7_TO_DOUBLE / TR7_FROM_DOUBLE reverse.
   function Encode_Double (A : System.Address) return Tr7_T is
     (From_U64 (Bits_Of_Address (A) + 6));

   --  The per-engine side arenas: doubles (with a dedupe cache, so equal
   --  doubles share one cell and compare equal) and the NUL-terminated
   --  text copies tr7_string_buffer / tr7_symbol_string hand to C.  Both
   --  are freed when the engine is destroyed.
   type Double_Cell;
   type Double_Ptr is access Double_Cell;
   type Double_Cell is record
      Value : Interfaces.C.double;
      Next  : Double_Ptr;
   end record;
   procedure Free_Double is new Ada.Unchecked_Deallocation
     (Double_Cell, Double_Ptr);

   Max_Double_Cache : constant := 64;
   type Double_Cache_Entry is record
      Bits : Interfaces.Unsigned_64 := 0;
      Item : Double_Ptr := null;
   end record;
   type Double_Cache_Array is
     array (0 .. Max_Double_Cache - 1) of Double_Cache_Entry;

   type Buffer_Cell;
   type Buffer_Ptr is access Buffer_Cell;
   type Buffer_Cell is record
      Text : Interfaces.C.Strings.chars_ptr;
      Next : Buffer_Ptr;
   end record;
   procedure Free_Buffer is new Ada.Unchecked_Deallocation
     (Buffer_Cell, Buffer_Ptr);

   Engine_Slot_Count : constant := 64;

   type Engine_Entry is record
      Live       : Boolean := False;
      Id         : Interfaces.Unsigned_32 := 0;  --  1 .. 65535, never reused
      Address    : System.Address := System.Null_Address;
      Doubles    : Double_Ptr := null;
      Cache      : Double_Cache_Array;
      Cache_Next : Natural range 0 .. Max_Double_Cache - 1 := 0;
      Buffers    : Buffer_Ptr := null;
   end record;

   --  One table for the whole process; the ABI is single-threaded by
   --  contract, like the rest of v1.
   Engine_Table : array (1 .. Engine_Slot_Count) of Engine_Entry;
   Next_Engine_Id : Interfaces.Unsigned_32 := 1;

   procedure Register_Engine
     (Eng        : Engine_Access;
      Id         : out Interfaces.Unsigned_32;
      Registered : out Boolean)
   is
   begin
      Id := 0;
      Registered := False;
      --  The id field is 16 bits and never reused; an id-space exhaustion
      --  is a creation failure, not a silent id wrap that would let stale
      --  values resolve into the wrong engine.
      if Next_Engine_Id > 65_535 then
         return;
      end if;
      for S in Engine_Table'Range loop
         if not Engine_Table (S).Live then
            Engine_Table (S) :=
              (Live       => True,
               Id         => Next_Engine_Id,
               Address    => Eng.all'Address,
               Doubles    => null,
               Cache      => (others => (Bits => 0, Item => null)),
               Cache_Next => 0,
               Buffers    => null);
            Id := Next_Engine_Id;
            Next_Engine_Id := Next_Engine_Id + 1;
            Registered := True;
            return;
         end if;
      end loop;
   end Register_Engine;

   procedure Unregister_Engine (Engine : System.Address) is
   begin
      for S in Engine_Table'Range loop
         if Engine_Table (S).Live
           and then Engine_Table (S).Address = Engine
         then
            while Engine_Table (S).Doubles /= null loop
               declare
                  D : Double_Ptr := Engine_Table (S).Doubles;
               begin
                  Engine_Table (S).Doubles := D.Next;
                  Free_Double (D);
               end;
            end loop;
            while Engine_Table (S).Buffers /= null loop
               declare
                  B : Buffer_Ptr := Engine_Table (S).Buffers;
               begin
                  Engine_Table (S).Buffers := B.Next;
                  Interfaces.C.Strings.Free (B.Text);
                  Free_Buffer (B);
               end;
            end loop;
            Engine_Table (S) :=
              (Live       => False,
               Id         => 0,
               Address    => System.Null_Address,
               Doubles    => null,
               Cache      => (others => (Bits => 0, Item => null)),
               Cache_Next => 0,
               Buffers    => null);
            return;
         end if;
      end loop;
   exception
      when others =>
         null;                    --  nothing may escape into C
   end Unregister_Engine;

   type Binding is record
      Slot : Natural range 0 .. Engine_Slot_Count := 0;
      Eng  : Engine_Access := null;
      Ok   : Boolean := False;
   end record;

   --  Validate an engine handle the way every ABI body does: null,
   --  misaligned and unregistered pointers all answer Ok => False and the
   --  caller returns its documented failure value.  Alignment alone would
   --  trust a forged pointer; the registry lookup is what actually says
   --  "this address is an engine this library created and has not freed".
   function Binding_Of (Engine : System.Address) return Binding is
      B : Binding;
   begin
      if Engine = System.Null_Address
        or else not Is_Aligned (Engine)
      then
         return B;
      end if;
      for S in Engine_Table'Range loop
         if Engine_Table (S).Live
           and then Engine_Table (S).Address = Engine
         then
            B.Slot := S;
            B.Eng := To_Engine (Engine);
            B.Ok := True;
            return B;
         end if;
      end loop;
      return B;
   end Binding_Of;

   type Resolved is record
      Slot : Natural range 0 .. Engine_Slot_Count := 0;
      Eng  : Engine_Access := null;
      Hd   : Tr7.Values.Handle := Tr7.Values.Null_Handle;
      Ok   : Boolean := False;
   end record;

   --  Resolve a heap-value tr7_t to its engine and handle.  The generation
   --  check inside Live_Cell is what rejects a value the collector has
   --  freed or an engine that no longer exists -- it answers Ok => False,
   --  never a wrong cell.
   function Resolve (T : Tr7_T) return Resolved is
      R : Resolved;
      Id : constant Interfaces.Unsigned_32 := Interfaces.Unsigned_32
        (Interfaces.Shift_Right (To_U64 (T), 47) and 16#FFFF#);
      Hd : constant Tr7.Values.Handle :=
        (Index => Tr7.Config.Cell_Index'Val
                    (Interfaces.Shift_Right (To_U64 (T), 3) and 16#FFF#),
         Generation => Interfaces.Unsigned_32
           (Interfaces.Shift_Right (To_U64 (T), 15) and 16#FFFF_FFFF#));
   begin
      if not Is_Heap_T (T) then
         return R;
      end if;
      for S in Engine_Table'Range loop
         if Engine_Table (S).Live and then Engine_Table (S).Id = Id then
            R.Slot := S;
            R.Eng := To_Engine (Engine_Table (S).Address);
            R.Hd := Hd;
            R.Ok := Tr7.Heap.Live_Cell (R.Eng.H, Hd) /= 0;
            return R;
         end if;
      end loop;
      R.Slot := 0;
      R.Eng := null;
      return R;
   end Resolve;

   type Resolved_Value is record
      Slot : Natural range 0 .. Engine_Slot_Count := 0;
      Eng  : Engine_Access := null;
      V    : Tr7.Values.Value := Tr7.Values.Nil_Value;
      Ok   : Boolean := False;
   end record;

   --  Resolve any tr7_t to a core Value.  Immediates decode straight from
   --  the bits and need no engine; a heap value resolves through Resolve.
   --  Host-forged fixnums outside the core's fixnum range have no
   --  representation and answer Ok => False.
   function Resolve_Value (T : Tr7_T) return Resolved_Value is
      R : Resolved_Value;
      HR : Resolved;
   begin
      if T = Tr7_Void then
         R.V := Tr7.Values.Void_Value;
         R.Ok := True;
      elsif T = Tr7_Nil then
         R.V := Tr7.Values.Nil_Value;
         R.Ok := True;
      elsif T = Tr7_True then
         R.V := Tr7.Values.True_Value;
         R.Ok := True;
      elsif T = Tr7_False then
         R.V := Tr7.Values.False_Value;
         R.Ok := True;
      elsif T = Tr7_Eof then
         R.V := Tr7.Values.Eof_Value;
         R.Ok := True;
      elsif Is_Fixnum_T (T) then
         declare
            N : constant Interfaces.Integer_64 := Int_Of_Bits
              (To_U64 (Decode_Int_Of (T)));
         begin
            if N in Tr7.Config.Fixnum_Min .. Tr7.Config.Fixnum_Max then
               R.V := Tr7.Values.From_Fixnum (N);
               R.Ok := True;
            end if;
         end;
      elsif Is_Char_T (T) then
         R.V := Tr7.Values.From_Character
           (Interfaces.Unsigned_32
              (Decode_Char_Of (T) and 16#FFFF_FFFF#));
         R.Ok := True;
      elsif Is_Double_T (T) then
         declare
            type Double_View is access all Interfaces.C.double;
            function To_Double_View is new Ada.Unchecked_Conversion
              (System.Address, Double_View);
         begin
            --  A tag-6 value is a pointer to a double, ours or one the
            --  host forged with TR7_FROM_DOUBLE; the header's own contract
            --  is that such a pointer is valid memory, so the dereference
            --  carries the same trust upstream's macros carry.
            R.V := Tr7.Values.From_Flonum
              (Long_Float
                 (To_Double_View (Address_Of_Bits (To_U64 (T) - 6)).all));
            R.Ok := True;
         end;
      elsif Is_Heap_T (T) then
         HR := Resolve (T);
         if HR.Ok then
            R.Slot := HR.Slot;
            R.Eng := HR.Eng;
            R.V := Tr7.Values.From_Handle (HR.Hd);
            R.Ok := True;
         end if;
      end if;
      return R;
   exception
      when others =>
         R.Ok := False;           --  forged garbage fails, never faults
         return R;
   end Resolve_Value;

   --  Allocate (or find cached) the backing double of a flonum value in
   --  slot's arena.  Cache hits make (eqv? 1.5 1.5) true, which upstream's
   --  allocate-per-call answer is not.
   procedure Value_Double
     (Slot : Natural; X : Interfaces.C.double; T : out Tr7_T; Ok : out Boolean)
   is
      Bits : constant Interfaces.Unsigned_64 := Bits_Of_Float (X);
   begin
      T := Tr7_Void;
      Ok := False;
      if Slot = 0 then
         return;
      end if;
      for I in Engine_Table (Slot).Cache'Range loop
         if Engine_Table (Slot).Cache (I).Item /= null
           and then Engine_Table (Slot).Cache (I).Bits = Bits
         then
            T := Encode_Double (Engine_Table (Slot).Cache (I).Item.all'Address);
            Ok := True;
            return;
         end if;
      end loop;
      declare
         D : constant Double_Ptr := new Double_Cell'(Value => X, Next => null);
      begin
         D.Next := Engine_Table (Slot).Doubles;
         Engine_Table (Slot).Doubles := D;
         Engine_Table (Slot).Cache (Engine_Table (Slot).Cache_Next) :=
           (Bits => Bits, Item => D);
         Engine_Table (Slot).Cache_Next :=
           (Engine_Table (Slot).Cache_Next + 1) mod Max_Double_Cache;
         T := Encode_Double (D.all'Address);
         Ok := True;
      end;
   exception
      when others =>
         Ok := False;             --  a full host heap is a TR7_NIL, not a fault
   end Value_Double;

   --  Value -> tr7_t.  Slot names the owning engine for handles and the
   --  flonum arena; Slot = 0 is only valid for immediate-only values.
   function From_Value
     (Slot : Natural; V : Tr7.Values.Value) return Tr7_T
   is
      T : Tr7_T;
      Ok : Boolean;
   begin
      case V.Kind is
         when Tr7.Values.Kind_Void | Tr7.Values.Kind_Unspecified =>
            return Tr7_Void;
         when Tr7.Values.Kind_Nil =>
            return Tr7_Nil;
         when Tr7.Values.Kind_Boolean =>
            return (if V.B then Tr7_True else Tr7_False);
         when Tr7.Values.Kind_EOF =>
            return Tr7_Eof;
         when Tr7.Values.Kind_Fixnum =>
            return Encode_Fixnum (V.N);
         when Tr7.Values.Kind_Character =>
            return Encode_Char (Interfaces.Unsigned_64 (V.C));
         when Tr7.Values.Kind_Flonum =>
            Value_Double (Slot, Interfaces.C.double (V.F), T, Ok);
            return (if Ok then T else Tr7_Void);
         when Tr7.Values.Kind_Handle =>
            if Slot = 0 then
               return Tr7_Nil;
            end if;
            return Encode_Heap (Engine_Table (Slot).Id, V.H);
      end case;
   end From_Value;

   --  Copy a NUL-terminated C string into the slot's buffer arena: the
   --  returned pointer stays valid until the engine is destroyed, which is
   --  the upstream lifetime shape without the GC coupling.  The host must
   --  not free it.
   function Arena_Copy
     (Slot : Natural; S : String; Ptr : out Interfaces.C.Strings.chars_ptr)
     return Boolean
   is
      Text : Interfaces.C.Strings.chars_ptr;
      B    : Buffer_Ptr;
   begin
      Ptr := Tr7_Null_String;
      if Slot = 0 or else S'Length > Tr7.Config.Max_Text then
         return False;
      end if;
      Text := Interfaces.C.Strings.New_String (S);
      B := new Buffer_Cell'(Text => Text, Next => Engine_Table (Slot).Buffers);
      Engine_Table (Slot).Buffers := B;
      Ptr := Text;
      return True;
   exception
      when others =>
         Interfaces.C.Strings.Free (Text);
         return False;
   end Arena_Copy;

   --  Read Count bytes at Ptr (no NUL scan): the length-parameterized C
   --  string entry points.
   function C_Bytes_Of (Ptr : System.Address; Len : Natural) return String is
      Result : String (1 .. Len);
      Arr : aliased Interfaces.C.char_array
        (0 .. Interfaces.C.size_t (Len - 1));
      for Arr'Address use Ptr;
   begin
      for I in 1 .. Len loop
         Result (I) := Interfaces.C.To_Ada
           (Arr (Interfaces.C.size_t (I - 1)));
      end loop;
      return Result;
   end C_Bytes_Of;

   --  NUL-terminated C string readers that tolerate a null pointer by
   --  answering the empty string, so every body can validate before it
   --  dereferences.
   function Value_Or_Empty (Ptr : System.Address) return String is
   begin
      if Ptr = System.Null_Address then
         return "";
      end if;
      return Interfaces.C.Strings.Value (To_Chars (Ptr));
   end Value_Or_Empty;

   function Value_Or_Empty (Ptr : Interfaces.C.Strings.chars_ptr)
     return String is
   begin
      if Ptr = Interfaces.C.Strings.Null_Ptr then
         return "";
      end if;
      return Interfaces.C.Strings.Value (Ptr);
   end Value_Or_Empty;

   --  The host array view for tr7_t[] parameters: the header's contract is
   --  that Count entries are readable, and every body bounds its reads
   --  with its own count check.
   Max_Host_Elements : constant := 4_096;
   type Tr7_Host_Array is
     array (0 .. Max_Host_Elements - 1) of aliased Tr7_T;
   type Tr7_Host_Array_Ptr is access all Tr7_Host_Array;
   function To_Host_Array is new Ada.Unchecked_Conversion
     (System.Address, Tr7_Host_Array_Ptr);

   --  The eq? callbacks of tr7_member / tr7_assoc, as the C header's
   --  `int (*)(tr7_t, tr7_t)`.
   type Eq_Callback is access function (A, B : Tr7_T) return Interfaces.C.int;
   pragma Convention (C, Eq_Callback);
   function To_Eq_Callback is new Ada.Unchecked_Conversion
     (System.Address, Eq_Callback);

   --  The last value the engine returned (load / run / eval / apply0):
   --  one slot, self-describing because heap values carry their engine.
   Last_Result_T   : Tr7_T := Tr7_Void;
   Has_Last_Result : Boolean := False;

   procedure Clear_Last_Result is
   begin
      Has_Last_Result := False;
      Last_Result_T := Tr7_Void;
   end Clear_Last_Result;

   procedure Set_Last_Result
     (Slot : Natural; V : Tr7.Values.Value)
   is
   begin
      Last_Result_T := From_Value (Slot, V);
      Has_Last_Result := True;
   exception
      when others =>
         Clear_Last_Result;       --  an unencodable result is no result
   end Set_Last_Result;

   --  Bounded structural equality, the body of tr7_equal: the fuel bounds
   --  recursion and pair walks, so cyclic structures answer 0 instead of
   --  hanging (upstream loops forever on one -- a documented deviation).
   function Equal_Values
     (Eng1 : Engine_Access; V1 : Tr7.Values.Value;
      Eng2 : Engine_Access; V2 : Tr7.Values.Value;
      Fuel : Natural)
     return Boolean
   is
      C1, C2 : Tr7.Cells.Cell;
      Good1, Good2 : Boolean;
   begin
      if Fuel = 0 then
         return False;
      end if;
      if Tr7.Values.Is_Handle (V1)
        and then Tr7.Values.Is_Handle (V2)
      then
         Tr7.Heap.Fetch (Eng1.H, Tr7.Values.To_Handle (V1), C1, Good1);
         Tr7.Heap.Fetch (Eng2.H, Tr7.Values.To_Handle (V2), C2, Good2);
         if not (Good1 and then Good2) then
            return False;
         end if;
         if C1.Kind /= C2.Kind then
            return False;
         end if;
         case C1.Kind is
            when Tr7.Cells.Cell_Pair =>
               return Equal_Values (Eng1, C1.Car, Eng2, C2.Car, Fuel - 1)
                 and then Equal_Values (Eng1, C1.Cdr, Eng2, C2.Cdr, Fuel - 1);
            when Tr7.Cells.Cell_Vector =>
               if C1.Arity /= C2.Arity then
                  return False;
               end if;
               return Equal_Values (Eng1, C1.Car, Eng2, C2.Car, Fuel - 1);
            when Tr7.Cells.Cell_String | Tr7.Cells.Cell_Symbol =>
               return C1.Name_Len = C2.Name_Len
                 and then C1.Name (1 .. C1.Name_Len)
                           = C2.Name (1 .. C2.Name_Len);
            when others =>
               return Tr7.Values.Same_Value (V1, V2);
         end case;
      end if;
      return Tr7.Values.Same_Value (V1, V2);
   end Equal_Values;

   --  The bounded list walk shared by the list operations: follows cdrs
   --  until the list ends and reports how many pairs it visited, so a
   --  cyclic list stops at the arena bound instead of hanging.
   procedure Walk_List
     (Eng     : Engine_Access;
      List    : Tr7.Values.Value;
      Visited : out Natural;
      Tail    : out Tr7.Values.Value;
      Cycled  : out Boolean)
   is
      Cur  : Tr7.Values.Value := List;
      Cdr  : Tr7.Values.Value;
      Ok   : Boolean;
      Count : Natural := 0;
   begin
      Visited := 0;
      Tail := Tr7.Values.Nil_Value;
      Cycled := False;
      loop
         if Tr7.Values.Is_Nil (Cur) then
            Visited := Count;
            Tail := Cur;
            return;
         end if;
         Tr7.Pairs.Cdr_Of (Eng.H, Cur, Cdr, Ok);
         if not Ok then
            --  Not a pair: the walk ends on the improper tail.
            Visited := Count;
            Tail := Cur;
            return;
         end if;
         if Count >= Tr7.Config.Max_Cells then
            --  An acyclic walk visits at most Max_Cells pairs (each pair
            --  is one arena cell), so this must be a cycle.
            Cycled := True;
            return;
         end if;
         Count := Count + 1;
         Cur := Cdr;
      end loop;
   end Walk_List;

   --  One shared core for the memq/memv/meme/assq/assv/asse and
   --  member/assoc wrappers.  For the mem family the match tests the pair
   --  car; for the ass family it tests the key of the (key . value) entry
   --  and the *entry* is returned.  Host_Eq selects the callback form.
   type Match_Kind is
     (Match_Eq, Match_Eqv, Match_Equal,
      Match_Ass_Eq, Match_Ass_Eqv, Match_Ass_Equal,
      Match_Member_Cb, Match_Assoc_Cb);

   function Search_List
     (X : Tr7_T; List : Tr7_T; Match : Match_Kind; Host_Eq : System.Address)
     return Tr7_T
   is
      RX : constant Resolved_Value := Resolve_Value (X);
      RL : constant Resolved_Value := Resolve_Value (List);
      Cur, Car, Cdr : Tr7.Values.Value;
      Ok : Boolean;
      Count : Natural := 0;
      CB : Eq_Callback;
   begin
      if not RL.Ok or else not RX.Ok then
         return Tr7_False;
      end if;
      if Match in Match_Member_Cb .. Match_Assoc_Cb then
         CB := To_Eq_Callback (Host_Eq);
         if CB = null then
            return Tr7_False;
         end if;
      end if;
      Cur := RL.V;
      loop
         if Tr7.Values.Is_Nil (Cur) then
            return Tr7_False;
         end if;
         if not Tr7.Values.Is_Handle (Cur) then
            return Tr7_False;     --  a non-pair tail ends the search
         end if;
         Tr7.Heap.Pair_Fields (RL.Eng.H, Tr7.Values.To_Handle (Cur),
                                Car, Cdr, Ok);
         if not Ok then
            return Tr7_False;     --  not a pair: the list ended badly
         end if;
         if Count >= Tr7.Config.Max_Cells then
            return Tr7_False;     --  cycle: upstream hangs or reports FALSE
         end if;
         Count := Count + 1;
         case Match is
            when Match_Eq | Match_Eqv | Match_Equal =>
               declare
                  Found : Boolean;
               begin
                  case Match is
                     when Match_Equal =>
                        Found := Equal_Values
                          (RX.Eng, RX.V, RL.Eng, Car, Tr7.Config.Max_Cells);
                     when others =>
                        Found := Tr7.Values.Same_Value (RX.V, Car);
                  end case;
                  if Found then
                     return From_Value (RL.Slot, Cur);
                  end if;
               end;
            when Match_Ass_Eq | Match_Ass_Eqv | Match_Ass_Equal |
                 Match_Assoc_Cb =>
               declare
                  Entry_Car, Entry_Cdr : Tr7.Values.Value;
                  Entry_Ok : Boolean;
                  Found : Boolean := False;
               begin
                  if Tr7.Values.Is_Handle (Car) then
                     Tr7.Heap.Pair_Fields
                       (RL.Eng.H, Tr7.Values.To_Handle (Car),
                        Entry_Car, Entry_Cdr, Entry_Ok);
                     if Entry_Ok then
                        case Match is
                           when Match_Ass_Equal =>
                              Found := Equal_Values
                                (RX.Eng, RX.V, RL.Eng, Entry_Car,
                                 Tr7.Config.Max_Cells);
                           when Match_Assoc_Cb =>
                              Found := CB (X, From_Value (RL.Slot, Entry_Car))
                                /= 0;
                           when others =>
                              Found :=
                                Tr7.Values.Same_Value (RX.V, Entry_Car);
                        end case;
                     end if;
                  end if;
                  if Found then
                     return From_Value (RL.Slot, Car);
                  end if;
               end;
            when Match_Member_Cb =>
               if CB (X, From_Value (RL.Slot, Car)) /= 0 then
                  return From_Value (RL.Slot, Cur);
               end if;
         end case;
         Cur := Cdr;
      end loop;
   exception
      when others =>
         return Tr7_False;        --  nothing may escape into C
   end Search_List;

   --  In-place reversal over values, the shared core of
   --  tr7_reverse_in_place and the copy-append path of tr7_append: rewires
   --  each pair's cdr and answers the new head.  Bounded by the arena.
   procedure Reverse_In_Place_Values
     (Eng    : Engine_Access;
      Head   : Tr7.Values.Value;
      Tail   : Tr7.Values.Value;
      Result : out Tr7.Values.Value;
      Ok     : out Boolean)
   is
      Prev, Cur, Next, Cdr : Tr7.Values.Value;
      Ok2 : Boolean;
      Count : Natural := 0;
   begin
      Prev := Tail;
      Cur := Head;
      Ok := False;
      loop
         if Tr7.Values.Is_Nil (Cur) then
            Result := Prev;
            Ok := True;
            return;
         end if;
         Tr7.Pairs.Cdr_Of (Eng.H, Cur, Cdr, Ok2);
         if not Ok2 then
            return;               --  not nil-terminated: caller answers VOID
         end if;
         if Count >= Tr7.Config.Max_Cells then
            return;               --  a cycle is caller-visible failure too
         end if;
         Tr7.Heap.Set_Cdr (Eng.H, Tr7.Values.To_Handle (Cur), Prev, Ok2);
         if not Ok2 then
            return;
         end if;
         Next := Cdr;
         Prev := Cur;
         Cur := Next;
         Count := Count + 1;
      end loop;
   end Reverse_In_Place_Values;

   --  Evaluate the NUL-terminated source: the shared body of load_string
   --  and tr7_run_string.  Print what ran, remember the last value, and --
   --  when requested -- report a trapped error the way tr7i does.  Nothing
   --  the engine keeps is exposed beyond the value slot, so a trapped
   --  error leaves the engine usable, exactly like load_string today.
   function Evaluate_Source
     (Engine : System.Address;
      Cmd    : Interfaces.C.Strings.chars_ptr;
      Report_Errors : Boolean)
     return Interfaces.C.int
   is
      B      : Binding;
      Src    : constant String := Interfaces.C.Strings.Value (Cmd);
      Result : Tr7.Values.Value;
      Status : Tr7.Runtime.Error_Code;
   begin
      B := Binding_Of (Engine);
      if not B.Ok then
         return 0;
      end if;

      --  Upstream's load contract: evaluate everything, trap the first
      --  error, and let the host carry on with the next load.
      Tr7.Engine.Reset_Output (B.Eng.all);
      Tr7.Engine.Evaluate (B.Eng.all, Src, Result, Status);
      Put_Out (Tr7.Engine.Output_Text (B.Eng.all));
      if Status /= Tr7.Runtime.No_Error then
         Clear_Last_Result;
         if Report_Errors then
            declare
               Msg : constant String := Tr7.Engine.Error_Message (B.Eng.all);
            begin
               if Msg'Length > 0 then
                  Put_Out ("error: " & Msg & ASCII.LF);
               else
                  Put_Out ("error: "
                             & Tr7.Runtime.Error_Name (Status) & ASCII.LF);
               end if;
            end;
         end if;
         Tr7.Engine.Reset_Output (B.Eng.all);
         return 0;
      end if;
      Tr7.Engine.Reset_Output (B.Eng.all);
      Set_Last_Result (B.Slot, Result);
      return 1;
   exception
      when others =>
         Clear_Last_Result;
         return 0;                --  nothing may escape into C
   end Evaluate_Source;

   Id_Ptr      : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.Null_Ptr;
   Version_Ptr : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.Null_Ptr;

   function Get_Id return Interfaces.C.Strings.chars_ptr is
   begin
      if Id_Ptr = Interfaces.C.Strings.Null_Ptr then
         Id_Ptr := Interfaces.C.Strings.New_String ("tr7-ada");
      end if;
      return Id_Ptr;
   exception
      when others =>
         return Interfaces.C.Strings.Null_Ptr;
   end Get_Id;

   function Get_Version return Interfaces.C.Strings.chars_ptr is
   begin
      if Version_Ptr = Interfaces.C.Strings.Null_Ptr then
         Version_Ptr := Interfaces.C.Strings.New_String ("0.1.0");
      end if;
      return Version_Ptr;
   exception
      when others =>
         return Interfaces.C.Strings.Null_Ptr;
   end Get_Version;

   procedure Config_Init_Default (Config : System.Address) is
      Defaults : constant Config_Record :=
        (Main_Dictionary_Size =>
           Interfaces.C.unsigned (Tr7.Config.Max_Env_Depth),
         Stack_Size_Max       =>
           Interfaces.C.unsigned (Tr7.Config.Max_Stack),
         Malloc               => C_Malloc'Address,
         Free                 => C_Free'Address);
   begin
      if Config /= System.Null_Address then
         To_Config_Ptr (Config).all := Defaults;
      end if;
   exception
      when others =>
         null;                    --  nothing may escape into C
   end Config_Init_Default;

   function Engine_Create (Config : System.Address) return System.Address is
      Eng : Engine_Access := null;
      Ok  : Boolean := False;
      Id  : Interfaces.Unsigned_32;
      Registered : Boolean;
   begin
      --  Upstream rejects a non-NULL config that lacks an allocator pair or
      --  a dictionary size; match that contract.  The values themselves are
      --  not honored -- the arena lives in Ada's heap -- which is the
      --  documented deviation, not a silent one.
      if Config /= System.Null_Address then
         if not Is_Aligned_Config (Config) then
            return System.Null_Address;
         end if;
         declare
            C : constant Config_Record := To_Config_Ptr (Config).all;
         begin
            if C.Malloc = System.Null_Address
              or else C.Free = System.Null_Address
              or else C.Main_Dictionary_Size = 0
            then
               return System.Null_Address;
            end if;
         end;
      end if;

      Eng := new Tr7.Engine.Engine;
      Tr7.Engine.Initialize (Eng.all, Ok);
      if not Ok then
         Free_Engine (Eng);
         return System.Null_Address;
      end if;

      --  The registry is what makes a tr7_t heap value resolvable: the
      --  encoding carries a 16-bit engine id that only this table can turn
      --  back into the engine object.  Ids are never reused, so a value
      --  that outlives its engine is always rejected, even when a new
      --  engine lands on the same address.  Without a free slot or an id
      --  left, engine creation fails the same way a full arena does.
      Register_Engine (Eng, Id, Registered);
      if not Registered then
         Free_Engine (Eng);
         return System.Null_Address;
      end if;
      return To_Address (Eng);
   exception
      when others =>
         if Eng /= null then
            Free_Engine (Eng);
         end if;
         return System.Null_Address;
   end Engine_Create;

   procedure Engine_Destroy (Engine : System.Address) is
      Eng : Engine_Access;
   begin
      if Engine /= System.Null_Address then
         --  Drop the registry entry (and with it every outstanding heap
         --  value of this engine) and release the ABI's side arenas before
         --  the engine object itself: nothing may dangle into C.
         Unregister_Engine (Engine);
         Eng := To_Engine (Engine);
         Free_Engine (Eng);
      end if;
   exception
      when others =>
         null;                    --  nothing may escape into C
   end Engine_Destroy;

   function Load_String
     (Engine : System.Address;
      Cmd    : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
   is
   begin
      --  Load is the trapping variant of the shared evaluator; run_string
      --  below shares this body with the error report turned off.
      if Cmd = Interfaces.C.Strings.Null_Ptr then
         return 0;
      end if;
      return Evaluate_Source (Engine, Cmd, Report_Errors => True);
   end Load_String;

   function Tr7_Run_String
     (Engine : System.Address;
      Cmd    : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
   is
   begin
      --  Run is load without the error report: 0 says "an error was
      --  raised", the host inspects the value slot.  Same engine, same
      --  output handling, same last-value discipline.
      if Cmd = Interfaces.C.Strings.Null_Ptr then
         return 0;
      end if;
      return Evaluate_Source (Engine, Cmd, Report_Errors => False);
   exception
      when others =>
         return 0;
   end Tr7_Run_String;

   --  Printing: one value through a local buffer, one flush.  The
   --  local-buffer bridge keeps the writer from touching the engine's own
   --  buffer (SPARK aliasing and C interleaving both want that), and the
   --  flush keeps C printf and ABI output in order.
   procedure Write_Item
     (Engine : System.Address; Item : Tr7_T; Display : Boolean)
   is
      B    : Binding;
      RV   : Resolved_Value;
      Buf  : Tr7.Runtime.Output_Buffer;
      Ok   : Boolean;
   begin
      B := Binding_Of (Engine);
      if not B.Ok then
         return;
      end if;
      RV := Resolve_Value (Item);
      if not RV.Ok then
         return;
      end if;
      if Tr7.Values.Is_Handle (RV.V) and then RV.Slot /= B.Slot then
         return;                  --  a foreign engine's object is unprintable here
      end if;
      Tr7.Runtime.Reset_Output (Buf);
      Tr7.Writer.Write_Value (B.Eng.H, RV.V, Buf, Ok, Display);
      Put_Out (String (Buf.Data (1 .. Buf.Len)));
   exception
      when others =>
         null;                    --  nothing may escape into C
   end Write_Item;

   function Tr7_Eq (A, B : Tr7_T) return Interfaces.C.int is
   begin
      --  eq? is raw equality of the encodings: immediates are canonical
      --  and a heap handle is its own identity.
      return (if A = B then 1 else 0);
   end Tr7_Eq;

   function Tr7_Eqv (A, B : Tr7_T) return Interfaces.C.int is
   begin
      --  Same relation: see the spec comment on why this matches eq? here
      --  (canonical immediates, identity handles, cached doubles).
      return (if A = B then 1 else 0);
   end Tr7_Eqv;

   function Tr7_Equal (A, B : Tr7_T) return Interfaces.C.int is
      RA : Resolved_Value;
      RB : Resolved_Value;
   begin
      RA := Resolve_Value (A);
      RB := Resolve_Value (B);
      if not (RA.Ok and then RB.Ok) then
         return 0;
      end if;
      return (if Equal_Values (RA.Eng, RA.V, RB.Eng, RB.V,
                               Tr7.Config.Max_Cells)
              then 1 else 0);
   exception
      when others =>
         return 0;
   end Tr7_Equal;

   function Tr7_From_Int
     (Engine : System.Address; Value : Tr7_T) return Tr7_T
   is
      pragma Unreferenced (Engine);  --  immediates touch no engine state
   begin
      --  Immediates touch no engine state, so a null engine is accepted.
      --  The core's fixnum range is the documented capacity: outside it
      --  the value has no representation and the answer is TR7_NIL.
      if Value in Tr7.Config.Fixnum_Min .. Tr7.Config.Fixnum_Max then
         return Encode_Fixnum (Interfaces.Integer_64 (Value));
      end if;
      return Tr7_Nil;
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_From_Int;

   function Tr7_To_Int (T : Tr7_T) return Tr7_T is
   begin
      if Is_Fixnum_T (T) then
         return Decode_Int_Of (T);
      end if;
      return 0;
   exception
      when others =>
         return 0;
   end Tr7_To_Int;

   function Tr7_Is_Integer (T : Tr7_T) return Interfaces.C.int is
   begin
      return (if Is_Fixnum_T (T) then 1 else 0);
   end Tr7_Is_Integer;

   function Tr7_From_Double
     (Engine : System.Address; Value : Interfaces.C.double) return Tr7_T
   is
      B  : Binding;
      T  : Tr7_T;
      Ok : Boolean;
   begin
      B := Binding_Of (Engine);
      if not B.Ok then
         return Tr7_Nil;
      end if;
      Value_Double (B.Slot, Value, T, Ok);
      return (if Ok then T else Tr7_Nil);
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_From_Double;

   function Tr7_To_Double (T : Tr7_T) return Interfaces.C.double is
      type Double_View is access all Interfaces.C.double;
      function To_Double_View is new Ada.Unchecked_Conversion
        (System.Address, Double_View);
   begin
      if Is_Double_T (T) then
         return To_Double_View (Address_Of_Bits (To_U64 (T) - 6)).all;
      end if;
      return 0.0;
   exception
      when others =>
         return 0.0;
   end Tr7_To_Double;

   function Tr7_Is_Char_Unicode (Value : Interfaces.C.unsigned_long)
     return Interfaces.C.int
   is
      V : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Value);
   begin
      --  A UNICODE scalar value: at most 16#10FFFF#, never a surrogate.
      return (if V <= 16#10FFFF#
                and then (V < 16#D800# or else V > 16#DFFF#)
              then 1 else 0);
   end Tr7_Is_Char_Unicode;

   function Tr7_From_Character
     (Engine : System.Address; Value : Interfaces.C.unsigned_long) return Tr7_T
   is
      pragma Unreferenced (Engine);  --  immediates touch no engine state
   begin
      --  Upstream's TR7_CHAR_MAX on an LP64 host; anything above it has no
      --  character encoding and answers the absent value.
      if Value > Tr7_Char_Max then
         return Tr7_Void;
      end if;
      return Encode_Char (Interfaces.Unsigned_64 (Value));
   exception
      when others =>
         return Tr7_Void;
   end Tr7_From_Character;

   function Tr7_To_Character (T : Tr7_T) return Interfaces.C.unsigned_long is
   begin
      if Is_Char_T (T) then
         return Interfaces.C.unsigned_long (Decode_Char_Of (T));
      end if;
      return 0;
   exception
      when others =>
         return 0;
   end Tr7_To_Character;

   function Tr7_Is_Character (T : Tr7_T) return Interfaces.C.int is
   begin
      return (if Is_Char_T (T) then 1 else 0);
   end Tr7_Is_Character;

   function Tr7_Is_Unicode_Character (T : Tr7_T) return Interfaces.C.int is
   begin
      if Is_Char_T (T) then
         return Tr7_Is_Char_Unicode
           (Interfaces.C.unsigned_long (Decode_Char_Of (T)));
      end if;
      return 0;
   exception
      when others =>
         return 0;
   end Tr7_Is_Unicode_Character;

   --  The cXr family: one walk, per-letter paths applied right-to-left
   --  (the letters of the C name between 'c' and 'r', outermost first).
   function Cxr_Walk (T : Tr7_T; Path : String) return Tr7_T
   with Pre => Path'Length in 1 .. 4
   is
      RV   : constant Resolved_Value := Resolve_Value (T);
      Cur  : Tr7.Values.Value;
      Res  : Tr7.Values.Value;
      Ok   : Boolean;
   begin
      if not RV.Ok then
         return Tr7_Void;
      end if;
      Cur := RV.V;
      for I in reverse Path'Range loop
         if Path (I) = 'a' then
            Tr7.Pairs.Car_Of (RV.Eng.H, Cur, Res, Ok);
         else
            Tr7.Pairs.Cdr_Of (RV.Eng.H, Cur, Res, Ok);
         end if;
         if not Ok then
            return Tr7_Void;     --  a step off a non-pair is the caller's VOID
         end if;
         Cur := Res;
      end loop;
      return From_Value (RV.Slot, Cur);
   exception
      when others =>
         return Tr7_Void;
   end Cxr_Walk;

   function Tr7_Car_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "a");
   end Tr7_Car_Or_Void;

   function Tr7_Cdr_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "d");
   end Tr7_Cdr_Or_Void;

   function Tr7_Caar_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "aa");
   end Tr7_Caar_Or_Void;

   function Tr7_Cadr_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "ad");
   end Tr7_Cadr_Or_Void;

   function Tr7_Cdar_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "da");
   end Tr7_Cdar_Or_Void;

   function Tr7_Cddr_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "dd");
   end Tr7_Cddr_Or_Void;

   function Tr7_Caaar_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "aaa");
   end Tr7_Caaar_Or_Void;

   function Tr7_Caadr_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "aad");
   end Tr7_Caadr_Or_Void;

   function Tr7_Cadar_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "ada");
   end Tr7_Cadar_Or_Void;

   function Tr7_Caddr_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "add");
   end Tr7_Caddr_Or_Void;

   function Tr7_Cdaar_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "daa");
   end Tr7_Cdaar_Or_Void;

   function Tr7_Cdadr_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "dad");
   end Tr7_Cdadr_Or_Void;

   function Tr7_Cddar_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "dda");
   end Tr7_Cddar_Or_Void;

   function Tr7_Cdddr_Or_Void (T : Tr7_T) return Tr7_T is
   begin
      return Cxr_Walk (T, "ddd");
   end Tr7_Cdddr_Or_Void;

   function Tr7_Cons
     (Engine : System.Address; A, B : Tr7_T) return Tr7_T
   is
      B1 : Binding;
      RA, RB : Resolved_Value;
      Res : Tr7.Values.Value;
      Ok  : Boolean;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok then
         return Tr7_Nil;
      end if;
      RA := Resolve_Value (A);
      RB := Resolve_Value (B);
      if not (RA.Ok and then RB.Ok) then
         return Tr7_Nil;
      end if;
      --  A pair's fields must belong to the arena that owns the pair:
      --  a foreign engine's handle has no meaning inside this heap, and
      --  the collector would mark it against the wrong arena.
      if (Tr7.Values.Is_Handle (RA.V) and then RA.Slot /= B1.Slot)
        or else (Tr7.Values.Is_Handle (RB.V) and then RB.Slot /= B1.Slot)
      then
         return Tr7_Nil;
      end if;
      Tr7.Pairs.Cons (B1.Eng.H, RA.V, RB.V, Res, Ok);
      if not Ok then
         return Tr7_Nil;          --  a full arena, as the header documents
      end if;
      return From_Value (B1.Slot, Res);
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Cons;

   function Tr7_Cons_N
     (Engine : System.Address;
      Count  : Interfaces.C.int;
      Cars   : System.Address;
      Cdr    : Tr7_T) return Tr7_T
   is
      B1 : Binding;
      Acc : Tr7.Values.Value;
      N   : Natural;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok then
         return Tr7_Nil;
      end if;
      if Count < 0 then
         return Tr7_Nil;          --  a negative count is a host bug
      end if;
      N := Natural (Count);
      if N > Max_Host_Elements then
         return Tr7_Nil;          --  beyond what the arena could hold anyway
      end if;
      if N > 0 and then Cars = System.Null_Address then
         return Tr7_Nil;
      end if;
      declare
         RC : constant Resolved_Value := Resolve_Value (Cdr);
      begin
         if not RC.Ok
           or else (Tr7.Values.Is_Handle (RC.V) and then RC.Slot /= B1.Slot)
         then
            return Tr7_Nil;
         end if;
         Acc := RC.V;
      end;
      --  Elements are consed right-to-left, so Cars[n-1] ends up the last
      --  car exactly as the header's list shape describes.
      if N > 0 then
         for I in reverse 0 .. N - 1 loop
            declare
               RV : constant Resolved_Value := Resolve_Value
                 (To_Host_Array (Cars) (Natural (I)));
            begin
               if not RV.Ok
                 or else (Tr7.Values.Is_Handle (RV.V)
                            and then RV.Slot /= B1.Slot)
               then
                  return Tr7_Nil;
               end if;
               declare
                  Elem : Tr7.Values.Value;
                  Ok : Boolean;
               begin
                  Tr7.Pairs.Cons (B1.Eng.H, RV.V, Acc, Elem, Ok);
                  if not Ok then
                     return Tr7_Nil;
                  end if;
                  Acc := Elem;
               end;
            end;
         end loop;
      end if;
      return From_Value (B1.Slot, Acc);
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Cons_N;

   function Tr7_List_Length (A : Tr7_T) return Interfaces.C.int is
      RV : constant Resolved_Value := Resolve_Value (A);
      Visited : Natural;
      Tail : Tr7.Values.Value;
      Cycled : Boolean;
   begin
      if not RV.Ok then
         return -2;               --  an unresolvable value is no list at all
      end if;
      Walk_List (RV.Eng, RV.V, Visited, Tail, Cycled);
      if Cycled then
         return -1;
      end if;
      if Tr7.Values.Is_Nil (Tail) then
         return Interfaces.C.int (Visited);
      end if;
      --  Upstream's improper-list contract: -2 minus the length before the
      --  dot ('(a b . c) is -4, a bare 42 is -2).
      return -Interfaces.C.int (Visited + 2);
   exception
      when others =>
         return -2;
   end Tr7_List_Length;

   function Tr7_Unsafe_List_Length (A : Tr7_T) return Interfaces.C.int is
      RV : constant Resolved_Value := Resolve_Value (A);
      Visited : Natural;
      Tail : Tr7.Values.Value;
      Cycled : Boolean;
   begin
      if not RV.Ok then
         return -1;
      end if;
      Walk_List (RV.Eng, RV.V, Visited, Tail, Cycled);
      if Cycled then
         --  Upstream never returns on a cycle; ours is bounded and answers
         --  the same improper-list shape at the bound (documented).
         return -Interfaces.C.int (Visited + 1);
      end if;
      if Tr7.Values.Is_Nil (Tail) then
         return Interfaces.C.int (Visited);
      end if;
      return -Interfaces.C.int (Visited + 1);
   exception
      when others =>
         return -1;
   end Tr7_Unsafe_List_Length;

   function Tr7_Reverse
     (Engine : System.Address; Head, Tail : Tr7_T) return Tr7_T
   is
      B1 : Binding;
      RH, RT : Resolved_Value;
      Acc, Elem, New_Acc, Next : Tr7.Values.Value;
      Ok : Boolean;
      Count : Natural := 0;
      Cur : Tr7.Values.Value;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok then
         return Tr7_Nil;
      end if;
      RH := Resolve_Value (Head);
      RT := Resolve_Value (Tail);
      if not RH.Ok or else not RT.Ok then
         return Tr7_Void;         --  a non-proper head is upstream's VOID
      end if;
      if (Tr7.Values.Is_Handle (RH.V) and then RH.Slot /= B1.Slot)
        or else (Tr7.Values.Is_Handle (RT.V) and then RT.Slot /= B1.Slot)
      then
         return Tr7_Nil;          --  cross-engine values cannot be copied here
      end if;
      --  Single pass: consing each visited car onto the accumulator builds
      --  the reversed copy directly, with the tail already at its end.
      Acc := RT.V;
      Cur := RH.V;
      loop
         if Tr7.Values.Is_Nil (Cur) then
            exit;
         end if;
         Tr7.Pairs.Car_Of (B1.Eng.H, Cur, Elem, Ok);
         if not Ok then
            return Tr7_Void;
         end if;
         Tr7.Pairs.Cons (B1.Eng.H, Elem, Acc, New_Acc, Ok);
         if not Ok then
            return Tr7_Nil;       --  a full arena, as the header documents
         end if;
         Acc := New_Acc;
         Tr7.Pairs.Cdr_Of (B1.Eng.H, Cur, Next, Ok);
         if not Ok then
            return Tr7_Void;
         end if;
         Cur := Next;
         Count := Count + 1;
         if Count > Tr7.Config.Max_Cells then
            return Tr7_Void;      --  a cycle: upstream would not return either
         end if;
      end loop;
      return From_Value (B1.Slot, Acc);
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Reverse;

   function Tr7_Reverse_In_Place (Head, Tail : Tr7_T) return Tr7_T is
      RH, RT : Resolved_Value;
      Res : Tr7.Values.Value;
      Ok  : Boolean;
   begin
      RH := Resolve_Value (Head);
      RT := Resolve_Value (Tail);
      if not RH.Ok or else not RT.Ok then
         return Tr7_Void;
      end if;
      --  Rewiring pairs mixes two engines' arenas only if the values come
      --  from different ones, which would corrupt both collectors: reject.
      if Tr7.Values.Is_Handle (RH.V)
        and then Tr7.Values.Is_Handle (RT.V)
        and then RH.Slot /= RT.Slot
      then
         return Tr7_Void;
      end if;
      if Tr7.Values.Is_Handle (RH.V) then
         Reverse_In_Place_Values (RH.Eng, RH.V, RT.V, Res, Ok);
         if not Ok then
            return Tr7_Void;
         end if;
         return From_Value (RH.Slot, Res);
      end if;
      --  Head is nil (or another non-pair): nothing to rewire.
      if Tr7.Values.Is_Nil (RH.V) then
         return From_Value (RT.Slot, RT.V);
      end if;
      return Tr7_Void;
   exception
      when others =>
         return Tr7_Void;
   end Tr7_Reverse_In_Place;

   function Tr7_Append
     (Engine : System.Address;
      Nitem  : Interfaces.C.int;
      Items  : System.Address) return Tr7_T
   is
      B1 : Binding;
      Acc : Tr7.Values.Value;
      N : Natural;
      Item_Value : Tr7.Values.Value;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok then
         return Tr7_Nil;
      end if;
      if Nitem = 0 then
         return Tr7_Nil;          --  (append) is the empty list
      end if;
      if Nitem < 0 or else Items = System.Null_Address then
         return Tr7_False;
      end if;
      N := Natural (Nitem);
      --  R7RS append: the last item is shared, every earlier one is copied
      --  and must be a proper list.
      declare
         RL : constant Resolved_Value := Resolve_Value
           (To_Host_Array (Items) (Natural (N - 1)));
      begin
         if not RL.Ok
           or else (Tr7.Values.Is_Handle (RL.V) and then RL.Slot /= B1.Slot)
         then
            return Tr7_False;
         end if;
         Item_Value := RL.V;
      end;
      Acc := Item_Value;
      if N > 1 then
         for I in reverse 0 .. N - 2 loop
            declare
               RI : constant Resolved_Value := Resolve_Value
                 (To_Host_Array (Items) (Natural (I)));
               Copy : Tr7.Values.Value;
               Copy_Ok : Boolean;
            begin
               if not RI.Ok
                 or else (Tr7.Values.Is_Handle (RI.V)
                            and then RI.Slot /= B1.Slot)
               then
                  return Tr7_False;
               end if;
               --  Copy the item: walk it forward consing onto nil (a
               --  reversed copy), then rewire that copy in place onto the
               --  accumulator -- one allocation per element, no scratch
               --  array.
               Walk_Copy : declare
                  Cur, Elem2, New_Copy, Next : Tr7.Values.Value;
                  Ok2 : Boolean;
                  Count : Natural := 0;
                  New_Acc : Tr7.Values.Value;
               begin
                  Cur := RI.V;
                  Copy := Tr7.Values.Nil_Value;
                  loop
                     if Tr7.Values.Is_Nil (Cur) then
                        exit;
                     end if;
                     Tr7.Pairs.Car_Of (B1.Eng.H, Cur, Elem2, Ok2);
                     if not Ok2 then
                        return Tr7_False;  --  improper: upstream's FALSE
                     end if;
                     Tr7.Pairs.Cons (B1.Eng.H, Elem2, Copy, New_Copy, Ok2);
                     if not Ok2 then
                        return Tr7_Nil;
                     end if;
                     Copy := New_Copy;
                     Count := Count + 1;
                     if Count > Tr7.Config.Max_Cells then
                        return Tr7_False;  --  cyclic list: upstream's FALSE
                     end if;
                     Tr7.Pairs.Cdr_Of (B1.Eng.H, Cur, Next, Ok2);
                     if not Ok2 then
                        return Tr7_False;
                     end if;
                     Cur := Next;
                  end loop;
                  Reverse_In_Place_Values
                    (B1.Eng, Copy, Acc, New_Acc, Copy_Ok);
                  if not Copy_Ok then
                     return Tr7_False;
                  end if;
                  Acc := New_Acc;
               end Walk_Copy;
            end;
         end loop;
      end if;
      return From_Value (B1.Slot, Acc);
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Append;

   function Tr7_Get_List_Cars
     (List  : Tr7_T;
      Count : Interfaces.C.int;
      Cars  : System.Address;
      Cdr   : System.Address) return Interfaces.C.int
   is
      type Tr7_Ptr is access all Tr7_T;
      function To_Tr7_Ptr is new Ada.Unchecked_Conversion
        (System.Address, Tr7_Ptr);
      RL : constant Resolved_Value := Resolve_Value (List);
      Cur, Car, Cdr_Value : Tr7.Values.Value;
      Ok : Boolean;
      Stored : Natural := 0;
      Cars_Arr : Tr7_Host_Array_Ptr;
   begin
      if Count < 0 then
         return 0;
      end if;
      if not RL.Ok then
         return 0;
      end if;
      if Count > 0 and then Cars /= System.Null_Address then
         Cars_Arr := To_Host_Array (Cars);
      end if;
      Cur := RL.V;
      while Stored < Natural (Count) loop
         if not Tr7.Values.Is_Handle (Cur) then
            exit;                 --  nil or an improper tail ends the walk
         end if;
         Tr7.Heap.Pair_Fields (RL.Eng.H, Tr7.Values.To_Handle (Cur),
                                Car, Cdr_Value, Ok);
         if not Ok then
            exit;
         end if;
         if Cars_Arr /= null then
            Cars_Arr (Stored) :=
              From_Value (RL.Slot, Car);
         end if;
         Stored := Stored + 1;
         Cur := Cdr_Value;
      end loop;
      if Cdr /= System.Null_Address then
         To_Tr7_Ptr (Cdr).all := From_Value (RL.Slot, Cur);
      end if;
      return Interfaces.C.int (Stored);
   exception
      when others =>
         return 0;
   end Tr7_Get_List_Cars;

   function Tr7_Memq (X, List : Tr7_T) return Tr7_T is
   begin
      return Search_List (X, List, Match_Eq, System.Null_Address);
   end Tr7_Memq;

   function Tr7_Memv (X, List : Tr7_T) return Tr7_T is
   begin
      --  eq and eqv agree on this encoding (see tr7_eqv), so both share
      --  the core's Same_Value relation.
      return Search_List (X, List, Match_Eqv, System.Null_Address);
   end Tr7_Memv;

   function Tr7_Meme (X, List : Tr7_T) return Tr7_T is
   begin
      return Search_List (X, List, Match_Equal, System.Null_Address);
   end Tr7_Meme;

   function Tr7_Assq (X, List : Tr7_T) return Tr7_T is
   begin
      return Search_List (X, List, Match_Ass_Eq, System.Null_Address);
   end Tr7_Assq;

   function Tr7_Assv (X, List : Tr7_T) return Tr7_T is
   begin
      return Search_List (X, List, Match_Ass_Eqv, System.Null_Address);
   end Tr7_Assv;

   function Tr7_Asse (X, List : Tr7_T) return Tr7_T is
   begin
      return Search_List (X, List, Match_Ass_Equal, System.Null_Address);
   end Tr7_Asse;

   function Tr7_Member
     (X, List : Tr7_T; Eq : System.Address) return Tr7_T
   is
   begin
      --  The host callback receives the encodings of x and the pair car;
      --  immediates arrive upstream-compatible, heap values as handles.
      return Search_List (X, List, Match_Member_Cb, Eq);
   end Tr7_Member;

   function Tr7_Assoc
     (X, List : Tr7_T; Eq : System.Address) return Tr7_T
   is
   begin
      return Search_List (X, List, Match_Assoc_Cb, Eq);
   end Tr7_Assoc;

   ---------------------------------------------------------------------
   --  Vectors.  A core vector is one cell whose Car is the proper list of
   --  its elements and whose Arity is the length, so every accessor is a
   --  bounded walk plus a field read, and every constructor is "build the
   --  element list, then allocate the cell".
   ---------------------------------------------------------------------

   --  Build an element list of Count copies of V, for make_vector_fill.
   procedure Element_List_Fill
     (Eng : Engine_Access; Count : Natural; V : Tr7.Values.Value;
      List : out Tr7.Values.Value; Ok : out Boolean)
   is
      Acc, Elem : Tr7.Values.Value;
      Cons_Ok : Boolean;
   begin
      Acc := Tr7.Values.Nil_Value;
      Ok := True;
      for I in 1 .. Count loop
         Tr7.Pairs.Cons (Eng.H, V, Acc, Elem, Cons_Ok);
         if not Cons_Ok then
            List := Tr7.Values.Nil_Value;
            Ok := False;
            return;
         end if;
         Acc := Elem;
      end loop;
      List := Acc;
   end Element_List_Fill;

   --  Build an element list by reading Count host entries (element i at
   --  Items[i * Stride]), in order, for make_vector_copy / _stride.  Arr
   --  is null only when Count is 0.
   procedure Element_List_Of
     (Eng : Engine_Access; Slot : Natural; Count : Natural;
      Arr : Tr7_Host_Array_Ptr; Stride : Interfaces.C.size_t;
      List : out Tr7.Values.Value; Ok : out Boolean)
   is
      Acc, Elem : Tr7.Values.Value;
      Cons_Ok : Boolean;
      RV : Resolved_Value;
   begin
      Acc := Tr7.Values.Nil_Value;
      Ok := True;
      if Count > 0 then
         for I in reverse 0 .. Count - 1 loop
            RV := Resolve_Value
              (Arr (Natural (Interfaces.Unsigned_64 (I) * Interfaces.Unsigned_64 (Stride))));
            if not RV.Ok
              or else (Tr7.Values.Is_Handle (RV.V) and then RV.Slot /= Slot)
            then
               List := Tr7.Values.Nil_Value;
               Ok := False;
               return;
            end if;
            Tr7.Pairs.Cons (Eng.H, RV.V, Acc, Elem, Cons_Ok);
            if not Cons_Ok then
               List := Tr7.Values.Nil_Value;
               Ok := False;
               return;
            end if;
            Acc := Elem;
         end loop;
      end if;
      List := Acc;
   end Element_List_Of;

   function Tr7_Make_Vector_Fill
     (Engine : System.Address;
      Len    : Interfaces.C.size_t;
      Value  : Tr7_T) return Tr7_T
   is
      B1 : Binding;
      RV : Resolved_Value;
      Elements : Tr7.Values.Value;
      Hd : Tr7.Values.Handle;
      Ok : Boolean;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok then
         return Tr7_Nil;
      end if;
      if Len > Interfaces.C.size_t (Tr7.Config.Max_List_Length) then
         return Tr7_Nil;          --  the documented vector capacity
      end if;
      RV := Resolve_Value (Value);
      if not RV.Ok
        or else (Tr7.Values.Is_Handle (RV.V) and then RV.Slot /= B1.Slot)
      then
         return Tr7_Nil;
      end if;
      Element_List_Fill (B1.Eng, Natural (Len), RV.V, Elements, Ok);
      if not Ok then
         return Tr7_Nil;
      end if;
      Tr7.Heap.New_Vector (B1.Eng.H, Elements, Natural (Len), Hd, Ok);
      if not Ok then
         return Tr7_Nil;
      end if;
      return From_Value (B1.Slot, Tr7.Values.From_Handle (Hd));
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Make_Vector_Fill;

   function Tr7_Make_Vector_Copy
     (Engine : System.Address;
      Len    : Interfaces.C.size_t;
      Items  : System.Address) return Tr7_T
   is
      B1 : Binding;
      Hd : Tr7.Values.Handle;
      Elements : Tr7.Values.Value;
      Ok : Boolean;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok then
         return Tr7_Nil;
      end if;
      if Len > Interfaces.C.size_t (Tr7.Config.Max_List_Length) then
         return Tr7_Nil;
      end if;
      if Len > 0 and then Items = System.Null_Address then
         return Tr7_Nil;
      end if;
      Element_List_Of (B1.Eng, B1.Slot, Natural (Len),
                       To_Host_Array (Items), 1, Elements, Ok);
      if not Ok then
         return Tr7_Nil;
      end if;
      Tr7.Heap.New_Vector (B1.Eng.H, Elements, Natural (Len), Hd, Ok);
      if not Ok then
         return Tr7_Nil;
      end if;
      return From_Value (B1.Slot, Tr7.Values.From_Handle (Hd));
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Make_Vector_Copy;

   function Tr7_Make_Vector_Stride
     (Engine : System.Address;
      Len    : Interfaces.C.size_t;
      Items  : System.Address;
      Stride : Interfaces.C.size_t) return Tr7_T
   is
      B1 : Binding;
      Hd : Tr7.Values.Handle;
      Elements : Tr7.Values.Value;
      Ok : Boolean;
      S : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Stride);
      L : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Len);
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok then
         return Tr7_Nil;
      end if;
      if L > Interfaces.Unsigned_64 (Tr7.Config.Max_List_Length)
        or else S = 0
        or else S > Interfaces.Unsigned_64 (Tr7.Config.Max_Cells)
        or else (L > 0
                   and then ((L - 1) * S
                               > Interfaces.Unsigned_64
                                   (Tr7.Config.Max_Cells * 1024)))
      then
         --  The last index (Len-1)*Stride must stay inside what the arena
         --  could plausibly back; the host array must still have the
         --  entries, which is the header's own contract.
         return Tr7_Nil;
      end if;
      if Len > 0 and then Items = System.Null_Address then
         return Tr7_Nil;
      end if;
      Element_List_Of (B1.Eng, B1.Slot, Natural (Len),
                       To_Host_Array (Items), Stride, Elements, Ok);
      if not Ok then
         return Tr7_Nil;
      end if;
      Tr7.Heap.New_Vector (B1.Eng.H, Elements, Natural (Len), Hd, Ok);
      if not Ok then
         return Tr7_Nil;
      end if;
      return From_Value (B1.Slot, Tr7.Values.From_Handle (Hd));
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Make_Vector_Stride;

   function Tr7_Vector_Length (Vec : Tr7_T) return Interfaces.C.size_t is
      RV : constant Resolved_Value := Resolve_Value (Vec);
      Kind : Tr7.Cells.Cell_Kind;
      Ok : Boolean;
      C : Tr7.Cells.Cell;
      Good : Boolean;
   begin
      if not RV.Ok then
         return 0;
      end if;
      Tr7.Heap.Kind_Of (RV.Eng.H, Tr7.Values.To_Handle (RV.V), Kind, Ok);
      if not Ok or else Kind /= Tr7.Cells.Cell_Vector then
         return 0;
      end if;
      Tr7.Heap.Fetch (RV.Eng.H, Tr7.Values.To_Handle (RV.V), C, Good);
      if not Good then
         return 0;
      end if;
      return Interfaces.C.size_t (C.Arity);
   exception
      when others =>
         return 0;
   end Tr7_Vector_Length;

   function Tr7_Vector_Ref
     (Vec : Tr7_T; Ielem : Interfaces.C.size_t) return Tr7_T
   is
      RV : constant Resolved_Value := Resolve_Value (Vec);
      Kind : Tr7.Cells.Cell_Kind;
      Ok : Boolean;
      C : Tr7.Cells.Cell;
      Good : Boolean;
      Cur, Elem : Tr7.Values.Value;
      I : Natural;
   begin
      if not RV.Ok then
         return Tr7_Void;
      end if;
      Tr7.Heap.Kind_Of (RV.Eng.H, Tr7.Values.To_Handle (RV.V), Kind, Ok);
      if not Ok or else Kind /= Tr7.Cells.Cell_Vector then
         return Tr7_Void;
      end if;
      Tr7.Heap.Fetch (RV.Eng.H, Tr7.Values.To_Handle (RV.V), C, Good);
      if not Good or else Natural (Ielem) >= C.Arity then
         return Tr7_Void;
      end if;
      --  Elements ride the Car list: an O(i) walk bounded by the arity.
      Cur := C.Car;
      I := 0;
      while I < Natural (Ielem) loop
         Tr7.Pairs.Cdr_Of (RV.Eng.H, Cur, Elem, Ok);
         if not Ok then
            return Tr7_Void;
         end if;
         Cur := Elem;
         I := I + 1;
      end loop;
      Tr7.Pairs.Car_Of (RV.Eng.H, Cur, Elem, Ok);
      if not Ok then
         return Tr7_Void;
      end if;
      return From_Value (RV.Slot, Elem);
   exception
      when others =>
         return Tr7_Void;
   end Tr7_Vector_Ref;

   function Tr7_Vector_Set
     (Vec   : Tr7_T;
      Ielem : Interfaces.C.size_t;
      Value : Tr7_T) return Tr7_T
   is
      RV : constant Resolved_Value := Resolve_Value (Vec);
      RW : constant Resolved_Value := Resolve_Value (Value);
      Kind : Tr7.Cells.Cell_Kind;
      Ok : Boolean;
      C : Tr7.Cells.Cell;
      Good : Boolean;
      Cur, Next : Tr7.Values.Value;
      I : Natural;
   begin
      if not RV.Ok or else not RW.Ok then
         return Tr7_Void;
      end if;
      if Tr7.Values.Is_Handle (RW.V) and then RW.Slot /= RV.Slot then
         return Tr7_Void;         --  a foreign engine's value cannot be stored
      end if;
      Tr7.Heap.Kind_Of (RV.Eng.H, Tr7.Values.To_Handle (RV.V), Kind, Ok);
      if not Ok or else Kind /= Tr7.Cells.Cell_Vector then
         return Tr7_Void;
      end if;
      Tr7.Heap.Fetch (RV.Eng.H, Tr7.Values.To_Handle (RV.V), C, Good);
      if not Good or else Natural (Ielem) >= C.Arity then
         return Tr7_Void;
      end if;
      Cur := C.Car;
      I := 0;
      while I < Natural (Ielem) loop
         Tr7.Pairs.Cdr_Of (RV.Eng.H, Cur, Next, Ok);
         if not Ok then
            return Tr7_Void;
         end if;
         Cur := Next;
         I := I + 1;
      end loop;
      Tr7.Heap.Set_Car (RV.Eng.H, Tr7.Values.To_Handle (Cur), RW.V, Ok);
      if not Ok then
         return Tr7_Void;
      end if;
      return Value;                --  upstream's answer: the value stored
   exception
      when others =>
         return Tr7_Void;
   end Tr7_Vector_Set;

   function Tr7_List_To_Vector
     (Engine : System.Address; List : Tr7_T) return Tr7_T
   is
      B1 : Binding;
      RL : Resolved_Value;
      Acc, Elem, New_Acc, Next, Cur : Tr7.Values.Value;
      Ok : Boolean;
      Count : Natural := 0;
      Hd : Tr7.Values.Handle;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok then
         return Tr7_Nil;
      end if;
      RL := Resolve_Value (List);
      if not RL.Ok
        or else (Tr7.Values.Is_Handle (RL.V) and then RL.Slot /= B1.Slot)
      then
         return Tr7_Nil;
      end if;
      --  Copy the list (the vector owns its element list), then allocate
      --  the vector cell over the copy.
      Acc := Tr7.Values.Nil_Value;
      Cur := RL.V;
      loop
         if Tr7.Values.Is_Nil (Cur) then
            exit;
         end if;
         Tr7.Pairs.Car_Of (B1.Eng.H, Cur, Elem, Ok);
         if not Ok then
            return Tr7_Nil;
         end if;
         Tr7.Pairs.Cons (B1.Eng.H, Elem, Acc, New_Acc, Ok);
         if not Ok then
            return Tr7_Nil;
         end if;
         Acc := New_Acc;
         Tr7.Pairs.Cdr_Of (B1.Eng.H, Cur, Next, Ok);
         if not Ok then
            return Tr7_Nil;
         end if;
         Cur := Next;
         Count := Count + 1;
         if Count > Tr7.Config.Max_List_Length then
            return Tr7_Nil;       --  the vector capacity
         end if;
      end loop;
      --  Acc is the reversed copy; rewire it into order and allocate.
      declare
         Head_Copy : constant Tr7.Values.Value := Acc;
      begin
         Reverse_In_Place_Values
           (B1.Eng, Head_Copy, Tr7.Values.Nil_Value, Acc, Ok);
      end;
      if not Ok then
         return Tr7_Nil;
      end if;
      Tr7.Heap.New_Vector (B1.Eng.H, Acc, Count, Hd, Ok);
      if not Ok then
         return Tr7_Nil;
      end if;
      return From_Value (B1.Slot, Tr7.Values.From_Handle (Hd));
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_List_To_Vector;

   function Tr7_Vector_To_List
     (Engine : System.Address; Vec : Tr7_T) return Tr7_T
   is
      B1 : Binding;
      RV : Resolved_Value;
      Kind : Tr7.Cells.Cell_Kind;
      Ok : Boolean;
      C : Tr7.Cells.Cell;
      Good : Boolean;
      Acc, Elem, New_Acc, Next, Cur : Tr7.Values.Value;
      I : Natural;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok then
         return Tr7_Nil;
      end if;
      RV := Resolve_Value (Vec);
      if not RV.Ok then
         return Tr7_Nil;
      end if;
      Tr7.Heap.Kind_Of (RV.Eng.H, Tr7.Values.To_Handle (RV.V), Kind, Ok);
      if not Ok or else Kind /= Tr7.Cells.Cell_Vector then
         return Tr7_Nil;
      end if;
      Tr7.Heap.Fetch (RV.Eng.H, Tr7.Values.To_Handle (RV.V), C, Good);
      if not Good then
         return Tr7_Nil;
      end if;
      --  Cons the elements onto the accumulator (a reversed list), then
      --  rewire it into order.
      Acc := Tr7.Values.Nil_Value;
      Cur := C.Car;
      I := 0;
      while I < C.Arity loop
         Tr7.Pairs.Car_Of (RV.Eng.H, Cur, Elem, Ok);
         if not Ok then
            return Tr7_Nil;
         end if;
         Tr7.Pairs.Cons (RV.Eng.H, Elem, Acc, New_Acc, Ok);
         if not Ok then
            return Tr7_Nil;
         end if;
         Acc := New_Acc;
         Tr7.Pairs.Cdr_Of (RV.Eng.H, Cur, Next, Ok);
         if not Ok then
            return Tr7_Nil;
         end if;
         Cur := Next;
         I := I + 1;
      end loop;
      declare
         Head_Copy : constant Tr7.Values.Value := Acc;
      begin
         Reverse_In_Place_Values
           (RV.Eng, Head_Copy, Tr7.Values.Nil_Value, Acc, Ok);
      end;
      if not Ok then
         return Tr7_Nil;
      end if;
      return From_Value (RV.Slot, Acc);
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Vector_To_List;

   ---------------------------------------------------------------------
   --  Strings and symbols.  Both are one cell with an inline text buffer
   --  capped at the core's Max_Text (256 bytes); v1 strings are bytes, so
   --  a "character" here is a byte and the length is the byte count --
   --  the documented v1 limit, not a UNICODE claim.
   ---------------------------------------------------------------------

   --  The text of a string or symbol cell, fetched by kind.
   procedure Text_Of_Kind
     (RV : Resolved_Value; Want : Tr7.Cells.Cell_Kind; Text : out String;
      Len : out Natural; Ok : out Boolean)
   is
      Kind : Tr7.Cells.Cell_Kind;
      Kind_Ok : Boolean;
      C : Tr7.Cells.Cell;
      Good : Boolean;
   begin
      Text := (others => ' ');
      Len := 0;
      Ok := False;
      if not RV.Ok then
         return;
      end if;
      Tr7.Heap.Kind_Of (RV.Eng.H, Tr7.Values.To_Handle (RV.V), Kind, Kind_Ok);
      if not Kind_Ok or else Kind /= Want then
         return;
      end if;
      Tr7.Heap.Fetch (RV.Eng.H, Tr7.Values.To_Handle (RV.V), C, Good);
      if not Good then
         return;
      end if;
      Len := C.Name_Len;
      Text (Text'First .. Text'First + C.Name_Len - 1) :=
        String (C.Name (1 .. C.Name_Len));
      Ok := True;
   end Text_Of_Kind;

   function Tr7_Make_String_Fill
     (Engine : System.Address;
      Car    : Interfaces.C.unsigned_long;
      Ncars  : Interfaces.C.size_t) return Tr7_T
   is
      B1 : Binding;
      Text : String (1 .. Natural (Ncars));
      Hd : Tr7.Values.Handle;
      Ok : Boolean;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok then
         return Tr7_Nil;
      end if;
      if Car > 255
        or else Ncars > Interfaces.C.size_t (Tr7.Config.Max_Text)
      then
         return Tr7_Nil;          --  a byte string cannot hold the character
      end if;
      for I in Text'Range loop
         Text (I) := Character'Val (Car);
      end loop;
      Tr7.Heap.New_String (B1.Eng.H, Text, Hd, Ok);
      if not Ok then
         return Tr7_Nil;
      end if;
      return From_Value (B1.Slot, Tr7.Values.From_Handle (Hd));
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Make_String_Fill;

   function Tr7_Make_String_Copy_Length
     (Engine : System.Address;
      Sutf8  : System.Address;
      Size   : Interfaces.C.size_t) return Tr7_T
   is
      B1 : Binding;
      Text : String (1 .. Natural (Size));
      Hd : Tr7.Values.Handle;
      Ok : Boolean;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok then
         return Tr7_Nil;
      end if;
      if Sutf8 = System.Null_Address then
         return Tr7_Nil;
      end if;
      if Size > Interfaces.C.size_t (Tr7.Config.Max_Text) then
         return Tr7_Nil;          --  the documented string capacity
      end if;
      --  The bytes are copied as they are: v1 does not validate UTF-8,
      --  which is the documented deviation from upstream's string rule.
      Text := C_Bytes_Of (Sutf8, Natural (Size));
      Tr7.Heap.New_String (B1.Eng.H, Text, Hd, Ok);
      if not Ok then
         return Tr7_Nil;
      end if;
      return From_Value (B1.Slot, Tr7.Values.From_Handle (Hd));
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Make_String_Copy_Length;

   function Tr7_Make_String_Copy
     (Engine : System.Address; Sutf8 : System.Address) return Tr7_T
   is
      B1 : Binding;
      Src : constant String := Value_Or_Empty (Sutf8);
      Hd : Tr7.Values.Handle;
      Ok : Boolean;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok
        or else Sutf8 = System.Null_Address
        or else Src'Length = 0
        or else Src'Length > Tr7.Config.Max_Text
      then
         return Tr7_Nil;
      end if;
      Tr7.Heap.New_String (B1.Eng.H, Src, Hd, Ok);
      if not Ok then
         return Tr7_Nil;
      end if;
      return From_Value (B1.Slot, Tr7.Values.From_Handle (Hd));
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Make_String_Copy;

   function Tr7_Make_String_Length
     (Engine : System.Address;
      Sutf8  : System.Address;
      Size   : Interfaces.C.size_t;
      Copy   : Interfaces.C.int) return Tr7_T
   is
   begin
      --  copy = 0 selects the static path, which adopts host memory this
      --  ABI cannot own; it reports TR7_NIL instead of aliasing silently.
      if Copy = 0 then
         return Tr7_Nil;
      end if;
      return Tr7_Make_String_Copy_Length (Engine, Sutf8, Size);
   end Tr7_Make_String_Length;

   function Tr7_Make_String
     (Engine : System.Address;
      Sutf8  : System.Address;
      Copy   : Interfaces.C.int) return Tr7_T
   is
   begin
      if Copy = 0 then
         return Tr7_Nil;
      end if;
      return Tr7_Make_String_Copy (Engine, Sutf8);
   end Tr7_Make_String;

   function Tr7_Is_String (T : Tr7_T) return Interfaces.C.int is
      RV : constant Resolved_Value := Resolve_Value (T);
      Kind : Tr7.Cells.Cell_Kind;
      Ok : Boolean;
   begin
      if RV.Ok then
         Tr7.Heap.Kind_Of (RV.Eng.H, Tr7.Values.To_Handle (RV.V), Kind, Ok);
         if Ok and then Kind = Tr7.Cells.Cell_String then
            return 1;
         end if;
      end if;
      return 0;
   exception
      when others =>
         return 0;
   end Tr7_Is_String;

   function Tr7_String_Size (T : Tr7_T) return Interfaces.C.size_t is
      Text : String (1 .. Tr7.Config.Max_Text);
      Len : Natural;
      Ok : Boolean;
   begin
      Text_Of_Kind (Resolve_Value (T), Tr7.Cells.Cell_String, Text, Len, Ok);
      return (if Ok then Interfaces.C.size_t (Len) else 0);
   exception
      when others =>
         return 0;
   end Tr7_String_Size;

   function Tr7_String_Buffer (T : Tr7_T) return Interfaces.C.Strings.chars_ptr is
      RV : constant Resolved_Value := Resolve_Value (T);
      Text : String (1 .. Tr7.Config.Max_Text);
      Len : Natural;
      Ok : Boolean;
      Ptr : Interfaces.C.Strings.chars_ptr;
   begin
      Text_Of_Kind (RV, Tr7.Cells.Cell_String, Text, Len, Ok);
      if not Ok then
         return Tr7_Null_String;
      end if;
      --  A fresh arena copy per call: the text inside the heap cell has no
      --  stable address a C host may keep, the arena copy does (until the
      --  engine is destroyed).
      if Arena_Copy (RV.Slot, Text (1 .. Len), Ptr) then
         return Ptr;
      end if;
      return Tr7_Null_String;
   exception
      when others =>
         return Tr7_Null_String;
   end Tr7_String_Buffer;

   function Tr7_String_Length (T : Tr7_T) return Interfaces.C.size_t is
   begin
      --  Byte length == byte size in v1; upstream counts UNICODE
      --  characters, which is the documented deviation.
      return Tr7_String_Size (T);
   end Tr7_String_Length;

   function Tr7_String_Ref
     (T  : Tr7_T;
      Pos : Interfaces.C.size_t) return Interfaces.C.unsigned_long
   is
      Text : String (1 .. Tr7.Config.Max_Text);
      Len : Natural;
      Ok : Boolean;
   begin
      Text_Of_Kind (Resolve_Value (T), Tr7.Cells.Cell_String, Text, Len, Ok);
      if Ok and then Pos < Interfaces.C.size_t (Len) then
         return Interfaces.C.unsigned_long
           (Character'Pos (Text (Natural (Pos) + 1)));
      end if;
      return Interfaces.C.unsigned_long'Last;  --  the header's -1 answer
   exception
      when others =>
         return Interfaces.C.unsigned_long'Last;
   end Tr7_String_Ref;

   function Tr7_String_Set
     (Engine : System.Address;
      T      : Tr7_T;
      Pos    : Interfaces.C.size_t;
      Car    : Interfaces.C.unsigned_long) return Interfaces.C.int
   is
      B1 : Binding;
      RV : constant Resolved_Value := Resolve_Value (T);
      Kind : Tr7.Cells.Cell_Kind;
      Kind_Ok : Boolean;
      C : Tr7.Cells.Cell;
      Good : Boolean;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok or else not RV.Ok then
         return 0;
      end if;
      if Tr7.Values.Is_Handle (RV.V) and then RV.Slot /= B1.Slot then
         return 0;                --  a foreign engine's string is untouchable
      end if;
      Tr7.Heap.Kind_Of (RV.Eng.H, Tr7.Values.To_Handle (RV.V), Kind, Kind_Ok);
      if not Kind_Ok or else Kind /= Tr7.Cells.Cell_String then
         return 0;
      end if;
      Tr7.Heap.Fetch (RV.Eng.H, Tr7.Values.To_Handle (RV.V), C, Good);
      if not Good
        or else Natural (Pos) >= C.Name_Len
        or else Car > 255
      then
         return 0;                --  the header's failure answer
      end if;
      --  In-place byte write, the same shape Heap.Set_Byte uses for
      --  bytevectors: the cell is live (generation-checked above) and no
      --  collection can run inside this call, so the direct arena write
      --  is safe.
      B1.Eng.H.Cells
        (Tr7.Config.Valid_Cell_Index (Tr7.Values.To_Handle (RV.V).Index))
          .Name (Natural (Pos) + 1) := Character'Val (Car);
      return 1;
   exception
      when others =>
         return 0;
   end Tr7_String_Set;

   function Tr7_Is_Symbol (T : Tr7_T) return Interfaces.C.int is
      RV : constant Resolved_Value := Resolve_Value (T);
      Kind : Tr7.Cells.Cell_Kind;
      Ok : Boolean;
   begin
      if RV.Ok then
         Tr7.Heap.Kind_Of (RV.Eng.H, Tr7.Values.To_Handle (RV.V), Kind, Ok);
         if Ok and then Kind = Tr7.Cells.Cell_Symbol then
            return 1;
         end if;
      end if;
      return 0;
   exception
      when others =>
         return 0;
   end Tr7_Is_Symbol;

   function Tr7_Symbol_String (T : Tr7_T) return Interfaces.C.Strings.chars_ptr is
      RV : constant Resolved_Value := Resolve_Value (T);
      Text : String (1 .. Tr7.Config.Max_Text);
      Len : Natural;
      Ok : Boolean;
      Ptr : Interfaces.C.Strings.chars_ptr;
   begin
      Text_Of_Kind (RV, Tr7.Cells.Cell_Symbol, Text, Len, Ok);
      if not Ok then
         return Tr7_Null_String;
      end if;
      if Arena_Copy (RV.Slot, Text (1 .. Len), Ptr) then
         return Ptr;
      end if;
      return Tr7_Null_String;
   exception
      when others =>
         return Tr7_Null_String;
   end Tr7_Symbol_String;

   function Tr7_Symbol_Size (T : Tr7_T) return Interfaces.C.size_t is
      Text : String (1 .. Tr7.Config.Max_Text);
      Len : Natural;
      Ok : Boolean;
   begin
      Text_Of_Kind (Resolve_Value (T), Tr7.Cells.Cell_Symbol, Text, Len, Ok);
      return (if Ok then Interfaces.C.size_t (Len) else 0);
   exception
      when others =>
         return 0;
   end Tr7_Symbol_Size;

   function Tr7_Symbol_Length (T : Tr7_T) return Interfaces.C.size_t is
   begin
      return Tr7_Symbol_Size (T);
   end Tr7_Symbol_Length;

   function Tr7_Symbol_Ref
     (T  : Tr7_T;
      Pos : Interfaces.C.size_t) return Interfaces.C.unsigned_long
   is
      Text : String (1 .. Tr7.Config.Max_Text);
      Len : Natural;
      Ok : Boolean;
   begin
      Text_Of_Kind (Resolve_Value (T), Tr7.Cells.Cell_Symbol, Text, Len, Ok);
      if Ok and then Pos < Interfaces.C.size_t (Len) then
         return Interfaces.C.unsigned_long
           (Character'Pos (Text (Natural (Pos) + 1)));
      end if;
      return Interfaces.C.unsigned_long'Last;
   exception
      when others =>
         return Interfaces.C.unsigned_long'Last;
   end Tr7_Symbol_Ref;

   function Tr7_Symbol_Lookup
     (Engine : System.Address;
      Name   : System.Address;
      Length : Interfaces.C.size_t;
      Copy   : Interfaces.C.int;
      Create : Interfaces.C.int) return Tr7_T
   is
      pragma Unreferenced (Copy);  --  both copy modes intern here, see above
      B1 : Binding;
      Src : String (1 .. Natural (Length));
      Sym : Tr7.Values.Value;
      Ok  : Boolean;
   begin
      B1 := Binding_Of (Engine);
      if not B1.Ok
        or else Name = System.Null_Address
        or else Length > Interfaces.C.size_t (Tr7.Config.Max_Text)
      then
         return Tr7_Nil;
      end if;
      Src := C_Bytes_Of (Name, Natural (Length));
      if Create /= 0 then
         --  Copy = 1 copies (our only mode), Copy = 0 would alias host
         --  memory upstream; both intern here, the documented deviation.
         Tr7.Heap.Intern (B1.Eng.H, Src, Sym, Ok);
         if not Ok then
            return Tr7_Nil;
         end if;
         return From_Value (B1.Slot, Sym);
      end if;
      --  Create = 0 must not allocate: scan the arena for the symbol.
      for I in Tr7.Config.Valid_Cell_Index loop
         declare
            C : constant Tr7.Cells.Cell := B1.Eng.H.Cells (I);
         begin
            if C.Kind = Tr7.Cells.Cell_Symbol
              and then C.Name_Len = Natural (Length)
              and then String (C.Name (1 .. C.Name_Len)) = Src
            then
               return From_Value
                 (B1.Slot,
                  Tr7.Values.From_Handle
                    (Tr7.Values.Handle'
                       (Index => I, Generation => C.Generation)));
            end if;
         end;
      end loop;
      return Tr7_False;            --  not interned, and none was created
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Symbol_Lookup;

   function Tr7_Get_Symbol_Length
     (Engine : System.Address;
      Name   : System.Address;
      Size   : Interfaces.C.size_t;
      Copy   : Interfaces.C.int) return Tr7_T
   is
   begin
      return Tr7_Symbol_Lookup (Engine, Name, Size, Copy, Create => 1);
   end Tr7_Get_Symbol_Length;

   function Tr7_Get_Symbol
     (Engine : System.Address;
      Name   : System.Address;
      Copy   : Interfaces.C.int) return Tr7_T
   is
      Src : constant String := Value_Or_Empty (Name);
   begin
      if Name = System.Null_Address or else Src'Length = 0 then
         return Tr7_Nil;
      end if;
      return Tr7_Get_Symbol_Length
        (Engine, Name, Interfaces.C.size_t (Src'Length), Copy);
   exception
      when others =>
         return Tr7_Nil;
   end Tr7_Get_Symbol;

   ---------------------------------------------------------------------
   --  Numeric and procedure predicates.
   ---------------------------------------------------------------------

   function Tr7_Is_Number (T : Tr7_T) return Interfaces.C.int is
   begin
      --  The v1 tower is fixnum + double, so number? = real?.
      return (if Is_Fixnum_T (T) or else Is_Double_T (T) then 1 else 0);
   end Tr7_Is_Number;

   function Tr7_Is_Real (T : Tr7_T) return Interfaces.C.int is
   begin
      return Tr7_Is_Number (T);
   end Tr7_Is_Real;

   function Tr7_Is_Exact (T : Tr7_T) return Interfaces.C.int is
   begin
      return (if Is_Fixnum_T (T) then 1 else 0);
   end Tr7_Is_Exact;

   function Tr7_Is_Exact_Integer (T : Tr7_T) return Interfaces.C.int is
   begin
      return Tr7_Is_Exact (T);
   end Tr7_Is_Exact_Integer;

   function Tr7_Is_Nan (T : Tr7_T) return Interfaces.C.int is
   begin
      if Is_Double_T (T) then
         declare
            X : constant Interfaces.C.double := Tr7_To_Double (T);
         begin
            --  NaN is the value that is not equal to itself; no IEEE
            --  attribute is needed and none exists in Ada.
            return (if X /= X then 1 else 0);
         end;
      end if;
      return 0;
   end Tr7_Is_Nan;

   function Tr7_Is_Infinite (T : Tr7_T) return Interfaces.C.int is
   begin
      if Is_Double_T (T) then
         declare
            X : constant Interfaces.C.double := Tr7_To_Double (T);
         begin
            --  NaN compares false, so it is not infinite; any finite
            --  double is at most Long_Float'Last in magnitude.
            return (if abs X > Interfaces.C.double (Long_Float'Last)
                    then 1 else 0);
         end;
      end if;
      return 0;
   end Tr7_Is_Infinite;

   function Tr7_Is_Finite (T : Tr7_T) return Interfaces.C.int is
   begin
      --  An exact integer is finite by definition; only the double path
      --  can carry an infinity or a NaN.
      if Is_Fixnum_T (T) then
         return 1;
      end if;
      if Is_Double_T (T) then
         declare
            X : constant Interfaces.C.double := Tr7_To_Double (T);
         begin
            return (if abs X <= Interfaces.C.double (Long_Float'Last)
                    then 1 else 0);
         end;
      end if;
      return 0;
   end Tr7_Is_Finite;

   function Tr7_Is_Procedure (T : Tr7_T) return Interfaces.C.int is
      RV : constant Resolved_Value := Resolve_Value (T);
      Kind : Tr7.Cells.Cell_Kind;
      Ok : Boolean;
   begin
      if RV.Ok then
         Tr7.Heap.Kind_Of (RV.Eng.H, Tr7.Values.To_Handle (RV.V), Kind, Ok);
         if Ok
           and then (Kind = Tr7.Cells.Cell_Closure
                       or else Kind = Tr7.Cells.Cell_Primitive
                       or else Kind = Tr7.Cells.Cell_Continuation)
         then
            return 1;
         end if;
      end if;
      return 0;
   exception
      when others =>
         return 0;
   end Tr7_Is_Procedure;

   function Tr7_Is_Closure (T : Tr7_T) return Interfaces.C.int is
      RV : constant Resolved_Value := Resolve_Value (T);
      Kind : Tr7.Cells.Cell_Kind;
      Ok : Boolean;
   begin
      if RV.Ok then
         Tr7.Heap.Kind_Of (RV.Eng.H, Tr7.Values.To_Handle (RV.V), Kind, Ok);
         if Ok and then Kind = Tr7.Cells.Cell_Closure then
            return 1;
         end if;
      end if;
      return 0;
   exception
      when others =>
         return 0;
   end Tr7_Is_Closure;

   ---------------------------------------------------------------------
   --  Printing, the value slot, and evaluation.
   ---------------------------------------------------------------------

   procedure Tr7_Write (Engine : System.Address; Item : Tr7_T) is
   begin
      Write_Item (Engine, Item, Display => False);
   end Tr7_Write;

   procedure Tr7_Write_Simple (Engine : System.Address; Item : Tr7_T) is
   begin
      --  No shared-structure notation exists in this implementation, so
      --  simple and shared coincide with write (documented deviation).
      Write_Item (Engine, Item, Display => False);
   end Tr7_Write_Simple;

   procedure Tr7_Write_Shared (Engine : System.Address; Item : Tr7_T) is
   begin
      Write_Item (Engine, Item, Display => False);
   end Tr7_Write_Shared;

   procedure Tr7_Display (Engine : System.Address; Item : Tr7_T) is
   begin
      Write_Item (Engine, Item, Display => True);
   end Tr7_Display;

   function Tr7_Display_String
     (Engine : System.Address; S : System.Address) return Interfaces.C.int
   is
   begin
      --  A plain C string through the same flushed channel; the engine is
      --  validated for symmetry with the other printing entry points.
      if Binding_Of (Engine).Ok and then S /= System.Null_Address then
         Put_Out (Interfaces.C.Strings.Value (To_Chars (S)));
         return 1;
      end if;
      return 0;
   exception
      when others =>
         return 0;
   end Tr7_Display_String;

   procedure Tr7_Flush (Engine : System.Address) is
      pragma Unreferenced (Engine);
   begin
      --  Only the stdio flush matters; the engine owns no buffered text of
      --  its own beyond what every write already flushed.
      if Interfaces.C_Streams.fflush (Interfaces.C_Streams.stdout) < 0 then
         null;                    --  a failed flush is the host's problem
      end if;
   end Tr7_Flush;

   function Tr7_Get_Values_Count (Engine : System.Address)
     return Interfaces.C.unsigned
   is
   begin
      if not Binding_Of (Engine).Ok then
         return 0;
      end if;
      return (if Has_Last_Result then 1 else 0);
   end Tr7_Get_Values_Count;

   function Tr7_Get_Value
     (Engine : System.Address;
      Index  : Interfaces.C.unsigned) return Tr7_T
   is
   begin
      --  The slot is self-describing, so any live engine may ask for it;
      --  a dead or forged engine pointer still answers VOID.
      if not Binding_Of (Engine).Ok then
         return Tr7_Void;
      end if;
      if Index = 0 and then Has_Last_Result then
         return Last_Result_T;
      end if;
      return Tr7_Void;
   end Tr7_Get_Value;

   function Tr7_Get_Last_Value (Engine : System.Address) return Tr7_T is
   begin
      return Tr7_Get_Value (Engine, 0);
   end Tr7_Get_Last_Value;

   function Tr7_Get_Values
     (Engine : System.Address;
      Count  : Interfaces.C.unsigned;
      Values : System.Address) return Interfaces.C.unsigned
   is
      type Tr7_Ptr is access all Tr7_T;
      function To_Tr7_Ptr is new Ada.Unchecked_Conversion
        (System.Address, Tr7_Ptr);
   begin
      if not Binding_Of (Engine).Ok
        or else Values = System.Null_Address
        or else Count = 0
        or else not Has_Last_Result
      then
         return 0;
      end if;
      To_Tr7_Ptr (Values).all := Last_Result_T;
      return 1;
   exception
      when others =>
         return 0;
   end Tr7_Get_Values;

   function Tr7_From_Utf8_Length
     (Engine : System.Address;
      Expr   : System.Address;
      Length : Interfaces.C.size_t) return Tr7_T
   is
      B  : Binding;
      Src : String (1 .. Natural (Length));
      Pos : Natural := 0;
      Datum : Tr7.Values.Value;
      Status : Tr7.Reader.Read_Status;
   begin
      B := Binding_Of (Engine);
      if not B.Ok
        or else Expr = System.Null_Address
        or else Length > Interfaces.C.size_t (Tr7.Config.Max_Text)
      then
         return Tr7_Void;
      end if;
      Src := C_Bytes_Of (Expr, Natural (Length));
      Tr7.Reader.Read_Datum (B.Eng.H, Src, Pos, Datum, Status);
      case Status is
         when Tr7.Reader.Read_Ok =>
            return From_Value (B.Slot, Datum);
         when Tr7.Reader.Read_End =>
            return Tr7_Eof;       --  the documented no-datum answer
         when others =>
            return Tr7_Void;      --  a parse or arena failure, as documented
      end case;
   exception
      when others =>
         return Tr7_Void;
   end Tr7_From_Utf8_Length;

   function Tr7_From_Utf8
     (Engine : System.Address; Expr : System.Address) return Tr7_T
   is
      B : Binding;
      Src : constant String := Value_Or_Empty (Expr);
      Pos : Natural := 0;
      Datum : Tr7.Values.Value;
      Status : Tr7.Reader.Read_Status;
   begin
      B := Binding_Of (Engine);
      if not B.Ok
        or else Expr = System.Null_Address
        or else Src'Length = 0
        or else Src'Length > Tr7.Config.Max_Text
      then
         return Tr7_Void;
      end if;
      Tr7.Reader.Read_Datum (B.Eng.H, Src, Pos, Datum, Status);
      case Status is
         when Tr7.Reader.Read_Ok =>
            return From_Value (B.Slot, Datum);
         when Tr7.Reader.Read_End =>
            return Tr7_Eof;
         when others =>
            return Tr7_Void;
      end case;
   exception
      when others =>
         return Tr7_Void;
   end Tr7_From_Utf8;

   function Tr7_Eval (Engine : System.Address; Obj : Tr7_T) return Tr7_T is
      B  : Binding;
      RV : Resolved_Value;
   begin
      B := Binding_Of (Engine);
      if not B.Ok then
         return Tr7_Void;
      end if;
      RV := Resolve_Value (Obj);
      if not RV.Ok
        or else (Tr7.Values.Is_Handle (RV.V) and then RV.Slot /= B.Slot)
      then
         Clear_Last_Result;
         return Tr7_Void;
      end if;
      --  The machine resets itself, collects at its own safe points and
      --  reports through M.Error, so evaluation through the ABI behaves
      --  exactly like one datum of load_string.
      Tr7.Machine.Evaluate (B.Eng.H, B.Eng.Global, RV.V, B.Eng.M,
                            B.Eng.Output);
      Put_Out (Tr7.Engine.Output_Text (B.Eng.all));
      Tr7.Engine.Reset_Output (B.Eng.all);
      if B.Eng.M.Error = Tr7.Runtime.No_Error then
         Set_Last_Result (B.Slot, B.Eng.M.Result);
         return From_Value (B.Slot, B.Eng.M.Result);
      end if;
      Clear_Last_Result;
      return Tr7_Void;
   exception
      when others =>
         Clear_Last_Result;
         return Tr7_Void;
   end Tr7_Eval;

   function Tr7_Apply0
     (Engine   : System.Address;
      Procname : Interfaces.C.Strings.chars_ptr) return Tr7_T
   is
      B  : Binding;
      Src : constant String := Value_Or_Empty (Procname);
      Sym : Tr7.Values.Value;
      Call, Elem : Tr7.Values.Value;
      Ok : Boolean;
   begin
      B := Binding_Of (Engine);
      if not B.Ok
        or else Procname = Interfaces.C.Strings.Null_Ptr
        or else Src'Length = 0
        or else Src'Length > Tr7.Config.Max_Text
      then
         return Tr7_Void;
      end if;
      Tr7.Heap.Intern (B.Eng.H, Src, Sym, Ok);
      if not Ok then
         return Tr7_Void;
      end if;
      --  Build (procname) and evaluate it: the same call the reader would
      --  produce, through the same machine path.
      Tr7.Pairs.Cons (B.Eng.H, Sym, Tr7.Values.Nil_Value, Elem, Ok);
      if not Ok then
         return Tr7_Void;
      end if;
      Call := Elem;
      Tr7.Machine.Evaluate (B.Eng.H, B.Eng.Global, Call, B.Eng.M,
                            B.Eng.Output);
      Put_Out (Tr7.Engine.Output_Text (B.Eng.all));
      Tr7.Engine.Reset_Output (B.Eng.all);
      if B.Eng.M.Error = Tr7.Runtime.No_Error then
         Set_Last_Result (B.Slot, B.Eng.M.Result);
         return From_Value (B.Slot, B.Eng.M.Result);
      end if;
      Clear_Last_Result;
      return Tr7_Void;
   exception
      when others =>
         Clear_Last_Result;
         return Tr7_Void;
   end Tr7_Apply0;

   procedure Tr7_Define
     (Engine : System.Address;
      Env    : Tr7_T;
      Symbol : Tr7_T;
      Value  : Tr7_T)
   is
      B  : Binding;
      RS : constant Resolved_Value := Resolve_Value (Symbol);
      RV : constant Resolved_Value := Resolve_Value (Value);
      Kind : Tr7.Cells.Cell_Kind;
      Kind_Ok : Boolean;
      Env_Hd : Tr7.Values.Handle;
      RE : Resolved_Value;
      Env_Kind : Tr7.Cells.Cell_Kind;
      Env_Ok : Boolean;
      Def_Ok : Boolean;
   begin
      B := Binding_Of (Engine);
      if not B.Ok
        or else not RS.Ok
        or else not RV.Ok
      then
         return;
      end if;
      if not Tr7.Values.Is_Handle (RS.V)
        or else RS.Slot /= B.Slot
        or else (Tr7.Values.Is_Handle (RV.V) and then RV.Slot /= B.Slot)
      then
         return;
      end if;
      Tr7.Heap.Kind_Of (B.Eng.H, Tr7.Values.To_Handle (RS.V), Kind, Kind_Ok);
      if not Kind_Ok or else Kind /= Tr7.Cells.Cell_Symbol then
         return;
      end if;
      if Env = Tr7_Void or else Env = Tr7_Nil then
         Env_Hd := B.Eng.Global;
      else
         RE := Resolve_Value (Env);
         if not RE.Ok
           or else RE.Slot /= B.Slot
           or else not Tr7.Values.Is_Handle (RE.V)
         then
            return;
         end if;
         Tr7.Heap.Kind_Of (B.Eng.H, Tr7.Values.To_Handle (RE.V),
                           Env_Kind, Env_Ok);
         if not Env_Ok or else Env_Kind /= Tr7.Cells.Cell_Environment then
            return;
         end if;
         Env_Hd := Tr7.Values.To_Handle (RE.V);
      end if;
      Tr7.Env.Define (B.Eng.H, Env_Hd, RS.V, RV.V, Def_Ok);
      --  A failed define (full arena) is silently dropped, upstream's
      --  void contract; nothing is half-bound.
   exception
      when others =>
         null;                    --  nothing may escape into C
   end Tr7_Define;

   function Tr7_Import_Lib
     (Engine : System.Address;
      Name   : System.Address) return Interfaces.C.int
   is
      B : Binding;
      Src : constant String := Value_Or_Empty (Name);
      Import_Sym : Tr7.Values.Value;
      Sym : Tr7.Values.Value;
      Parts : Tr7.Values.Value;
      Elem, New_Elem, Lib_List : Tr7.Values.Value;
      Ok : Boolean;
      Next : Natural;
      Part : String (1 .. Tr7.Config.Max_Text);
      Part_Len : Natural;
      Part_Count : Natural := 0;
      Ended_With_Separator : Boolean := False;
   begin
      B := Binding_Of (Engine);
      if not B.Ok
        or else Name = System.Null_Address
        or else Src'Length = 0
        or else Src'Length > Tr7.Config.Max_Text
      then
         return -3;               --  -Tr7_GetLib_Error_Not_Found
      end if;
      Next := Src'First;
      Tr7.Heap.Intern (B.Eng.H, "import", Import_Sym, Ok);
      if not Ok then
         return -5;               --  -Tr7_GetLib_Error_Eval
      end if;
      --  Split the slash-separated name into its parts; an empty part (a
      --  doubled or trailing slash) is an invalid name, as upstream says.
      Parts := Tr7.Values.Nil_Value;
      while Next <= Src'Last loop
         Part_Len := 0;
         while Next <= Src'Last and then Src (Next) /= '/' loop
            Part_Len := Part_Len + 1;
            Part (Part_Len) := Src (Next);
            Next := Next + 1;
         end loop;
         if Part_Len = 0 or else Part_Count >= 32 then
            return -1;            --  -Tr7_GetLib_Error_Invalid_Name
         end if;
         Part_Count := Part_Count + 1;
         --  A numeric part stays a fixnum, exactly as the reader would
         --  read it in (srfi 1): the core's import handler matches the 1
         --  as an exact integer, not as a symbol.  Non-digit parts intern.
         declare
            Digits_Only : Boolean := Part_Len > 0;
         begin
            for I in 1 .. Part_Len loop
               if Part (I) not in '0' .. '9' then
                  Digits_Only := False;
               end if;
            end loop;
            if Digits_Only and then Part_Len <= 9 then
               declare
                  N : constant Interfaces.Integer_64 := Interfaces.Integer_64'Value
                    (Part (1 .. Part_Len));
               begin
                  if N in Tr7.Config.Fixnum_Min .. Tr7.Config.Fixnum_Max then
                     Sym := Tr7.Values.From_Fixnum (N);
                     Ok := True;
                  else
                     Ok := False;
                  end if;
               end;
            else
               Tr7.Heap.Intern (B.Eng.H, Part (1 .. Part_Len), Sym, Ok);
            end if;
         end;
         if not Ok then
            return -5;
         end if;
         Tr7.Pairs.Cons (B.Eng.H, Sym, Parts, New_Elem, Ok);
         if not Ok then
            return -5;
         end if;
         Parts := New_Elem;
         Ended_With_Separator := Next <= Src'Last;
         Next := Next + 1;        --  past the slash
      end loop;
      if Ended_With_Separator then
         return -1;               --  a trailing slash names an empty part
      end if;
      --  Parts was built reversed; rewire it into order and wrap it in
      --  (import (...)), then evaluate that form.
      declare
         Parts_Copy : constant Tr7.Values.Value := Parts;
      begin
         Reverse_In_Place_Values
           (B.Eng, Parts_Copy, Tr7.Values.Nil_Value, Lib_List, Ok);
      end;
      if not Ok then
         return -5;
      end if;
      Tr7.Pairs.Cons (B.Eng.H, Lib_List, Tr7.Values.Nil_Value, Elem, Ok);
      if not Ok then
         return -5;
      end if;
      Lib_List := Elem;
      Tr7.Pairs.Cons (B.Eng.H, Import_Sym, Lib_List, Elem, Ok);
      if not Ok then
         return -5;
      end if;
      --  A numeric part stays a fixnum, exactly as the reader would read
      --  (srfi 1): the core's import handler matches the 1 of (srfi 1)
      --  as an exact integer, not as a symbol.
      Tr7.Machine.Evaluate (B.Eng.H, B.Eng.Global, Elem, B.Eng.M,
                            B.Eng.Output);
      Put_Out (Tr7.Engine.Output_Text (B.Eng.all));
      Tr7.Engine.Reset_Output (B.Eng.all);
      if B.Eng.M.Error = Tr7.Runtime.No_Error then
         Set_Last_Result (B.Slot, B.Eng.M.Result);
         return 0;                --  Tr7_GetLib_No_Error
      end if;
      Clear_Last_Result;
      return -5;                  --  -Tr7_GetLib_Error_Eval
   exception
      when others =>
         Clear_Last_Result;
         return -5;
   end Tr7_Import_Lib;

end Tr7_C;
