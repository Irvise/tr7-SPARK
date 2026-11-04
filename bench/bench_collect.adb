with Ada.Text_IO; use Ada.Text_IO;
with Ada.Real_Time; use Ada.Real_Time;
with Tr7.Config; use Tr7.Config;
with Tr7.Heap; use Tr7.Heap;
with Tr7.Machine; use Tr7.Machine;
with Tr7.Values; use Tr7.Values;
procedure Bench_Collect is
   H : Heap_Type;
   M : Machine;
   T : Time;
   D : Duration;
   N : constant := 612;
begin
   Initialize (H);
   M := (others => <>);

   T := Clock;
   for K in 1 .. N loop
      Collect_Garbage (H, Null_Handle, M);
   end loop;
   D := To_Duration (Clock - T);
   Put_Line ("empty collect x" & Integer'Image (N) & " :" & Duration'Image (D)
             & "  per =" & Duration'Image (D / N));
end Bench_Collect;
