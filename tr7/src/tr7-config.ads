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

   --  Mark-sweep collector.  Collection only ever runs at a safe point (the
   --  top of the evaluator loop, between steps, and between datums in the
   --  engine's read loop), where the CEK state plus the global environment
   --  are a complete root set.  Two thresholds govern the trigger:
   --
   --    * GC_Low_Water is the hard floor: below it a collection always
   --      runs.  It is heuristic headroom, not a guarantee: a single
   --      allocation-heavy step (list-copy, append) can still need more,
   --      and allocation then reports heap exhausted.
   --    * GC_Soft_Water catches stale garbage before the floor does: a
   --      collection also runs below GC_Soft_Water when the previous one
   --      was productive (freed at least GC_Low_Water cells).  A burst of
   --      short-lived allocations leaves unreachable cells above the hard
   --      floor; without this, that garbage sits uncollected until an
   --      allocation-heavy step fails.  The productivity condition stops
   --      the soft trigger from collecting on every step of a loop whose
   --      live set simply fills the arena -- a collection that freed
   --      nothing buys no headroom.
   GC_Low_Water  : constant := 512;
   GC_Soft_Water : constant := 3 * GC_Low_Water;

   --  Under --stress-gc a collection runs every this many evaluator steps
   --  rather than every one: one sweep touches the whole arena, so every
   --  step would be dominated by memory bandwidth.  Nine still gives tens
   --  of thousands of collections over a test run.
   GC_Stress_Every : constant := 9;

   --  Exact integers are fixnums in -(2**31) .. 2**31 - 1.  Two properties
   --  drive this choice:
   --
   --    * R7RS only requires exact integers throughout the range usable as
   --      indexes of lists, vectors, bytevectors and strings and as the result
   --      of their length procedures -- far below 2**30 here -- and permits
   --      an implementation to report a restriction outside its range;
   --    * the product of two fixnums then fits in Integer_64 (at most 2**62),
   --      so exact multiplication is one direct multiply plus a range check,
   --      an obligation GNATprove discharges with constant-bound arithmetic.
   --      A wider fixnum needs a wide multiply whose exactness is beyond the
   --      SMT provers; see docs/findings.md.
   Fixnum_Min : constant := -(2 ** 31);
   Fixnum_Max : constant := 2 ** 31 - 1;

end Tr7.Config;
