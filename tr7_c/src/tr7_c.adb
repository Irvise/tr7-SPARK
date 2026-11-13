with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Interfaces.C_Streams;
with System.Storage_Elements;
with Tr7.Config;
with Tr7.Engine;
with Tr7.Runtime;
with Tr7.Values;

package body Tr7_C with SPARK_Mode => Off is

   --  The comparison operators of types the contracts and bodies lean on
   --  are not directly visible through a with clause alone.
   use type Interfaces.C.unsigned;
   use type System.Storage_Elements.Integer_Address;
   use type Tr7.Runtime.Error_Code;

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

   --  The identity strings are built on first use, not at elaboration: a C
   --  main links this library without an Ada binder, so nothing here may
   --  depend on elaboration having run.  Single-threaded by contract, like
   --  the rest of v1.
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
         Eng := To_Engine (Engine);
         Free_Engine (Eng);
      end if;
   exception
      when others =>
         null;                    --  nothing may escape into C
   end Engine_Destroy;

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

   function Load_String
     (Engine : System.Address;
      Cmd    : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
   is
      Eng    : Engine_Access;
      Result : Tr7.Values.Value;
      Status : Tr7.Runtime.Error_Code;
   begin
      if Engine = System.Null_Address
        or else Cmd = Interfaces.C.Strings.Null_Ptr
        or else not Is_Aligned (Engine)
      then
         return 0;
      end if;
      Eng := To_Engine (Engine);

      --  Upstream's load contract: evaluate everything, trap the first
      --  error, report it, return 0 -- and let the host carry on with the
      --  next load.
      declare
         Src : constant String := Interfaces.C.Strings.Value (Cmd);
      begin
         Tr7.Engine.Reset_Output (Eng.all);
         Tr7.Engine.Evaluate (Eng.all, Src, Result, Status);
         Put_Out (Tr7.Engine.Output_Text (Eng.all));
         if Status /= Tr7.Runtime.No_Error then
            declare
               Msg : constant String := Tr7.Engine.Error_Message (Eng.all);
            begin
               if Msg'Length > 0 then
                  Put_Out ("error: " & Msg & ASCII.LF);
               else
                  Put_Out ("error: "
                             & Tr7.Runtime.Error_Name (Status) & ASCII.LF);
               end if;
            end;
            Tr7.Engine.Reset_Output (Eng.all);
            return 0;
         end if;
         Tr7.Engine.Reset_Output (Eng.all);
         return 1;
      end;
   exception
      when others =>
         return 0;                --  nothing may escape into C
   end Load_String;

end Tr7_C;
