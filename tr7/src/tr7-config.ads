--  TR7-SPARK configuration.
--
--  All capacities are static so that the verified core needs no allocator and
--  no access types.  They are deliberately modest; increase them for larger
--  workloads after re-running the proof.

package Tr7.Config with
   SPARK_Mode => On
is

   Max_Cells : constant := 4_096;
   type Cell_Index is range 0 .. Max_Cells;
   subtype Valid_Cell_Index is Cell_Index range 1 .. Max_Cells;

   Max_Text : constant := 256;
   Max_Stack : constant := 4_096;
   Max_Arguments : constant := 256;
   Max_List_Length : constant := 1_024;
   Max_Env_Depth : constant := 1_024;
   Max_Print_Depth : constant := 256;
   Max_Reader_Depth : constant := 256;
   Max_Output : constant := 4_096;
   Max_Steps : constant := 1_000_000;

   Fixnum_Min : constant := -2 ** 61;
   Fixnum_Max : constant := 2 ** 61 - 1;

end Tr7.Config;
