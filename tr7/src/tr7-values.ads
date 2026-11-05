--  Scheme values.
--
--  Values deliberately form a non-variant record with an explicit kind.  This
--  avoids discriminant checks in the verified core and makes it cheap to prove
--  that every accessor is only used on the right kind of value.  Heap
--  references are index+generation handles, never access values.

with Interfaces; use Interfaces;
with Tr7.Config; use Tr7.Config;

package Tr7.Values with
   SPARK_Mode => On
is

   type Value_Kind is
     (Kind_Void,
      Kind_Boolean,
      Kind_Fixnum,
      Kind_Flonum,
      Kind_Character,
      Kind_Nil,
      Kind_Handle,
      Kind_Unspecified,
      --  What `read` returns past the end of a port.
      Kind_EOF);

   type Handle is record
      Index      : Cell_Index := 0;
      Generation : Unsigned_32 := 0;
   end record;

   Null_Handle : constant Handle := (Index => 0, Generation => 0);

   type Value is record
      Kind : Value_Kind := Kind_Void;
      N    : Integer_64 := 0;
      C    : Unsigned_32 := 0;
      B    : Boolean := False;
      H    : Handle := Null_Handle;
      --  An IEEE double: a flonum is immediate like a fixnum, so it needs no
      --  cell and the collector never sees it.
      F    : Long_Float := 0.0;
   end record;

   type Value_Array is array (1 .. Max_Arguments) of Value;

   Void_Value        : constant Value := (Kind => Kind_Void, others => <>);
   Nil_Value         : constant Value := (Kind => Kind_Nil, others => <>);
   Unspecified_Value : constant Value := (Kind => Kind_Unspecified, others => <>);
   Eof_Value         : constant Value := (Kind => Kind_EOF, others => <>);
   True_Value        : constant Value := (Kind => Kind_Boolean, B => True, others => <>);
   False_Value       : constant Value := (Kind => Kind_Boolean, B => False, others => <>);

   function Is_Void (V : Value) return Boolean is
     (V.Kind = Kind_Void);

   function Is_Nil (V : Value) return Boolean is
     (V.Kind = Kind_Nil);

   function Is_Boolean (V : Value) return Boolean is
     (V.Kind = Kind_Boolean);

   function Is_EOF (V : Value) return Boolean is
     (V.Kind = Kind_EOF);

   function Is_Fixnum (V : Value) return Boolean is
     (V.Kind = Kind_Fixnum);

   function Is_Character (V : Value) return Boolean is
     (V.Kind = Kind_Character);

   function Is_Handle (V : Value) return Boolean is
     (V.Kind = Kind_Handle);

   function Is_False (V : Value) return Boolean is
     (V.Kind = Kind_Boolean and then not V.B);

   function Is_True (V : Value) return Boolean is
     (not Is_False (V));

   function To_Boolean (V : Value) return Boolean is
     (V.B)
     with Pre => V.Kind = Kind_Boolean;

   function From_Boolean (B : Boolean) return Value is
     (if B then True_Value else False_Value);

   function To_Fixnum (V : Value) return Integer_64 is
     (V.N)
     with Pre => V.Kind = Kind_Fixnum;

   function From_Fixnum (N : Integer_64) return Value is
     ((Kind => Kind_Fixnum, N => N, others => <>))
     with Pre => N in Fixnum_Min .. Fixnum_Max;

   function From_Flonum (X : Long_Float) return Value is
     ((Kind => Kind_Flonum, F => X, others => <>));

   function Is_Flonum (V : Value) return Boolean is
     (V.Kind = Kind_Flonum);

   --  The operand as a Long_Float: an exact integer converted (every fixnum
   --  is far inside a double's range) or the flonum itself.
   function As_Float (V : Value) return Long_Float is
     (if V.Kind = Kind_Fixnum then Long_Float (V.N) else V.F)
     with Pre => V.Kind = Kind_Fixnum or else V.Kind = Kind_Flonum;

   function To_Character (V : Value) return Unsigned_32 is
     (V.C)
     with Pre => V.Kind = Kind_Character;

   function From_Character (C : Unsigned_32) return Value is
     ((Kind => Kind_Character, C => C, others => <>));

   function To_Handle (V : Value) return Handle is
     (V.H)
     with Pre => V.Kind = Kind_Handle;

   function From_Handle (H : Handle) return Value is
     ((Kind => Kind_Handle, H => H, others => <>));

   function Same_Handle (A, B : Handle) return Boolean is
     (A.Index = B.Index and then A.Generation = B.Generation);

   --  The relation behind `eq?`, and behind the datum lists of `case`
   --  (which R7RS compares with memv): immediate values compare by content,
   --  heap values -- symbols, strings, pairs -- by identity.
   function Same_Value (A, B : Value) return Boolean is
     (if A.Kind /= B.Kind then False
      else (case A.Kind is
               when Kind_Void | Kind_Nil | Kind_Unspecified => True,
               when Kind_Boolean   => A.B = B.B,
               when Kind_Fixnum    => A.N = B.N,
               when Kind_Flonum    => A.F = B.F,
               when Kind_Character => A.C = B.C,
               when Kind_Handle    => Same_Handle (A.H, B.H),
               when Kind_EOF        => True));

end Tr7.Values;
